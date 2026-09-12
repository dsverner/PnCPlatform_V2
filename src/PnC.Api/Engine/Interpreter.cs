using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Endpoints;
using PnC.Formula;

namespace PnC.Api.Engine;

// PROCEDURE-ENGINE §3–§6 (W4, decision #106: decisions in C#, writes in procedures). The interpreter walks a procedure
// instance's block tree against its pinned canonical document, evaluates every expression with PnC.Formula over the
// live catalogue (DbFactReader), and advances the run through the process.* procedures — one procedure per state
// change, each its own transaction. It is re-entrant and idempotent: Advance can run any number of times (after a
// commit, on the sweep, on demand) and only changes what the state and the facts say must change (§4.1).
//   block kinds: sequence · step · choice · parallel (branches) · foreach (members) · repeat (passes) · call · hold
//   Unknown: a precondition holds the step (facts named); a choice with all cases Unknown, a repeat.until Unknown, a
//   parallel.applies Unknown and a foreach.over Unknown hold their block for a person (§7).

public sealed record BlockRow(Guid EntityId, Guid? ParentEntityId, string Path, string Kind, string? IterationKey, int Pass, string? MemberKind, Guid? MemberId,
    string State, string? Outcome, DateTimeOffset? StartedAt, DateTimeOffset? CompletedAt, long RowSeq,
    Guid? StepEntityId, string? StepId, string? StepState, string? StepOutcome, DateTimeOffset? CommittedAt, string? HeldReason)
{
    public bool Terminal => State is "Completed" or "Skipped" or "Cancelled";
}

public sealed class DocBlock
{
    public required string Path { get; init; }
    public required string Kind { get; init; }
    public required JsonObject Node { get; init; }
    public DocBlock? Parent { get; init; }
    public List<DocBlock> Children { get; } = new();
    /// <summary>For foreach / repeat: the body block; for a branch: its body; for a choice: the case bodies then the else.</summary>
    public string? Id => Node["id"]?.GetValue<string>();
}

public sealed class Interpreter(SqlSession session, Catalog catalog, ILogger log)
{
    public sealed record Instance(Guid EntityId, Guid VersionRowId, string SubjectKind, Guid SubjectEntityId, Guid? WorkRequestEntityId, Guid? WorkflowInstanceEntityId,
        string State, string? Outcome, JsonObject Document, JsonObject Produced, JsonObject Inputs, DocBlock Root, List<BlockRow> Rows);

    // ------------------------------------------------------------------ loading
    public async Task<Instance> LoadAsync(Guid instanceId, CancellationToken ct)
    {
        var args = new Dictionary<string, object?> { ["@i"] = instanceId };
        var head = (await session.RowsAsync("""
            SELECT i.EntityId, i.DefinitionVersionRowId, i.SubjectKind, i.SubjectEntityId, i.WorkRequestEntityId, i.WorkflowInstanceEntityId, i.State, i.Outcome, i.Produced, i.Inputs, dv.PayloadText
            FROM process.vProcedureInstance i JOIN config.vDefinitionVersion dv ON dv.RowId = i.DefinitionVersionRowId WHERE i.EntityId = @i
            """, args, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_instance", "No procedure instance has that id.");
        var doc = (JsonObject)JsonNode.Parse(head["PayloadText"]!.GetValue<string>())!;
        var root = BuildDoc(doc["body"] as JsonObject ?? throw new ApiException(500, "internal", "The pinned document has no body."), null, head["SubjectKind"]!.GetValue<string>());
        var rows = await LoadRowsAsync(instanceId, ct);
        JsonObject J(string k) => head[k] is JsonValue v && v.TryGetValue<string>(out var s) && s.Length > 0 ? (JsonObject)(JsonNode.Parse(s) ?? new JsonObject()) : new JsonObject();
        return new Instance(instanceId, Guid.Parse(head["DefinitionVersionRowId"]!.GetValue<string>()), head["SubjectKind"]!.GetValue<string>(), Guid.Parse(head["SubjectEntityId"]!.GetValue<string>()),
            G(head["WorkRequestEntityId"]), G(head["WorkflowInstanceEntityId"]), head["State"]!.GetValue<string>(), head["Outcome"]?.GetValue<string>(), doc, J("Produced"), J("Inputs"), root, rows);
    }

    private async Task<List<BlockRow>> LoadRowsAsync(Guid instanceId, CancellationToken ct)
    {
        var rows = await session.RowsAsync("SELECT * FROM process.vProcedureInstanceTree WHERE ProcedureInstanceEntityId = @i ORDER BY BlockRowSeq", new Dictionary<string, object?> { ["@i"] = instanceId }, ct);
        return rows.Select(r => (JsonObject)r!).Select(r => new BlockRow(
            Guid.Parse(r["BlockInstanceEntityId"]!.GetValue<string>()), G(r["ParentBlockInstanceEntityId"]), r["BlockPath"]!.GetValue<string>(), r["BlockKind"]!.GetValue<string>(),
            r["IterationKey"]?.GetValue<string>(), r["Pass"]?.GetValue<int>() ?? 1, r["MemberSubjectKind"]?.GetValue<string>(), G(r["MemberSubjectEntityId"]),
            r["BlockState"]!.GetValue<string>(), r["BlockOutcome"]?.GetValue<string>(), D(r["BlockStartedAt"]), D(r["BlockCompletedAt"]), r["BlockRowSeq"]!.GetValue<long>(),
            G(r["StepInstanceEntityId"]), r["StepId"]?.GetValue<string>(), r["StepState"]?.GetValue<string>(), r["StepOutcome"]?.GetValue<string>(), D(r["CommittedAt"]), r["HeldReason"]?.GetValue<string>())).ToList();
    }

    private static Guid? G(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) && Guid.TryParse(s, out var g) ? g : null;
    private static DateTimeOffset? D(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) && DateTimeOffset.TryParse(s, out var d) ? d : null;

    /// <summary>The document's block tree with the same paths fProcedureBlocks assigns (branches included, choice cases adding no segment, an id-less sequence sharing its parent's path).</summary>
    public static DocBlock BuildDoc(JsonObject node, DocBlock? parent, string subjectKind, string? parentPath = null)
    {
        var kind = node["block"]?.GetValue<string>() ?? "branch";
        var id = node["id"]?.GetValue<string>();
        var path = parent is null ? (id ?? "") : (id is null ? parentPath! : parentPath + "/" + id);
        var b = new DocBlock { Path = path, Kind = kind, Node = node, Parent = parent };
        switch (kind)
        {
            case "sequence": foreach (var it in node["items"] as JsonArray ?? new()) b.Children.Add(BuildDoc((JsonObject)it!, b, subjectKind, path)); break;
            case "parallel": foreach (var br in node["branches"] as JsonArray ?? new()) b.Children.Add(BuildDoc((JsonObject)br!, b, subjectKind, path)); break;
            case "branch": b.Children.Add(BuildDoc((JsonObject)node["body"]!, b, subjectKind, path)); break;
            case "choice":
                foreach (var c in node["cases"] as JsonArray ?? new()) b.Children.Add(BuildDoc((JsonObject)c!["body"]!, b, subjectKind, path));
                if (node["else"] is JsonObject e) b.Children.Add(BuildDoc(e, b, subjectKind, path));
                break;
            case "foreach": case "repeat": b.Children.Add(BuildDoc((JsonObject)node["body"]!, b, subjectKind, path)); break;
        }
        return b;
    }

    // ------------------------------------------------------------------ evaluation
    private InstanceContext Context(Instance inst) => new()
    {
        InstanceEntityId = inst.EntityId, Document = inst.Document, Produced = inst.Produced, Inputs = inst.Inputs,
        CaptureTypes = CaptureTypes(inst.Root),
    };

    private static Dictionary<string, IReadOnlyDictionary<string, JsonObject>> CaptureTypes(DocBlock root)
    {
        var d = new Dictionary<string, IReadOnlyDictionary<string, JsonObject>>(StringComparer.Ordinal);
        void Walk(DocBlock b)
        {
            if (b.Kind == "step" && b.Node["capture"] is JsonObject cap)
                d[b.Id!] = cap.ToDictionary(kv => kv.Key, kv => (JsonObject)kv.Value!, StringComparer.Ordinal);
            foreach (var c in b.Children) Walk(c);
        }
        Walk(root);
        return d;
    }

    public sealed record Verdict(bool? Value, IReadOnlyList<string> Unknowns, object? Raw)
    {
        public static Verdict True => new(true, [], true);
    }

    /// <summary>Evaluates a boolean expression node for a block: the subject is the enclosing member (a foreach body) or the instance's subject; step facts see the current member and pass.</summary>
    public Verdict EvalBool(Instance inst, JsonObject expr, BlockRow? at, DateTimeOffset now, IReadOnlyDictionary<string, object>? env = null)
    {
        var r = Eval(inst, expr, at, now, env);
        return r.Value switch { bool b => new Verdict(b, r.Unknowns, b), _ => new Verdict(null, r.Unknowns, r.Value) };
    }

    public EvalResult Eval(Instance inst, JsonObject expr, BlockRow? at, DateTimeOffset now, IReadOnlyDictionary<string, object>? env = null)
    {
        var ctx = Context(inst);
        var (member, memberKind, pass) = Scope(inst, at);
        ctx.CurrentMember = member?.ToString();
        ctx.CurrentPass = pass;
        var subject = member is not null ? new Ref(member.Value.ToString(), memberKind ?? "Any") : new Ref(inst.SubjectEntityId.ToString(), inst.SubjectKind);
        var reader = new DbFactReader(session.Connection, ctx);
        return Evaluator.Evaluate(expr, reader, subject, now, env);
    }

    /// <summary>The member subject and pass a block row sits in (its own or the nearest ancestor's).</summary>
    private static (Guid? member, string? kind, int? pass) Scope(Instance inst, BlockRow? row)
    {
        Guid? member = null; string? kind = null; int? pass = null;
        var r = row;
        while (r is not null)
        {
            if (member is null && r.MemberId is not null) { member = r.MemberId; kind = r.MemberKind; }
            if (pass is null && r.Pass > 1) pass = r.Pass;
            r = r.ParentEntityId is null ? null : inst.Rows.FirstOrDefault(x => x.EntityId == r.ParentEntityId);
        }
        return (member, kind, pass ?? (row is null ? null : 1));
    }

    // ------------------------------------------------------------------ advancing
    public sealed class AdvanceResult { public int Changes; public bool Completed; public List<string> Notes = new(); }

    /// <summary>Re-evaluates and advances the whole instance until nothing more moves (§4.1). Safe to call at any time.</summary>
    public async Task<AdvanceResult> AdvanceAsync(Guid instanceId, DateTimeOffset now, CancellationToken ct)
    {
        var result = new AdvanceResult();
        for (var iteration = 0; iteration < 40; iteration++)
        {
            var inst = await LoadAsync(instanceId, ct);
            if (inst.State is "Completed" or "Cancelled") { result.Completed = true; return result; }
            var before = result.Changes;
            var root = inst.Rows.FirstOrDefault(r => r.ParentEntityId is null) ?? throw new ApiException(500, "internal", "The instance has no root block.");
            await ProcessAsync(inst, inst.Root, root, now, result, ct);
            if (root.Terminal || (await LoadRowsAsync(instanceId, ct)).First(r => r.EntityId == root.EntityId).Terminal)
            {
                var outcome = inst.Document["outcomes"] is JsonArray oc && oc.Count > 0 ? oc[0]!.GetValue<string>() : "Completed";
                await Exec("CompleteInstance", new JsonObject { ["ProcedureInstanceEntityId"] = instanceId.ToString(), ["State"] = "Completed", ["Outcome"] = outcome, ["At"] = now }, ct);
                result.Changes++; result.Completed = true; result.Notes.Add($"instance completed: {outcome}");
                return result;
            }
            if (result.Changes == before) return result;
        }
        result.Notes.Add("advance stopped after 40 iterations");
        log.LogWarning("Interpreter: instance {Instance} did not settle in 40 iterations", instanceId);
        return result;
    }

    private BlockRow? RowOf(Instance inst, DocBlock doc, BlockRow? parent, string? iterationKey, int pass)
        => inst.Rows.FirstOrDefault(r => r.Path == doc.Path && r.Kind == doc.Kind && r.ParentEntityId == parent?.EntityId && r.IterationKey == iterationKey && r.Pass == pass);

    private IEnumerable<BlockRow> ChildRows(Instance inst, BlockRow parent) => inst.Rows.Where(r => r.ParentEntityId == parent.EntityId).OrderBy(r => r.RowSeq);

    private async Task ProcessAsync(Instance inst, DocBlock doc, BlockRow row, DateTimeOffset now, AdvanceResult res, CancellationToken ct)
    {
        if (row.Terminal) return;
        switch (doc.Kind)
        {
            case "sequence":
            {
                if (row.State == "Pending") { await SetBlock(row, "Running", null, now, ct); res.Changes++; }
                foreach (var childDoc in doc.Children)
                {
                    var child = RowOf(inst, childDoc, row, row.IterationKey, row.Pass);
                    if (child is null) { res.Notes.Add($"no row for {childDoc.Kind} {childDoc.Path}"); return; }
                    if (child.Terminal) continue;
                    await ProcessAsync(inst, childDoc, child, now, res, ct);
                    return;      // a sequence waits on its first unfinished item
                }
                await SetBlock(row, "Completed", "Done", now, ct); res.Changes++;
                return;
            }
            case "step":
            {
                if (row.StepState is "Pending" or "Held")
                {
                    if (doc.Node["precondition"] is JsonObject pre)
                    {
                        var v = EvalBool(inst, pre, row, now);
                        if (v.Value == true) { await SetStep(row, "Ready", null, ct); res.Changes++; }
                        else if (v.Value is null) { var reason = "precondition unknown: " + string.Join(", ", v.Unknowns.Distinct()); if (row.StepState != "Held" || row.HeldReason != reason) { await SetStep(row, "Held", reason, ct); res.Changes++; } }
                        // false: the step waits; its branch can still be ended by a branch outcome (the C1 check guarantees one exists)
                    }
                    else if (row.StepState == "Pending") { await SetStep(row, "Ready", null, ct); res.Changes++; }
                }
                return;   // Ready / Active: a person's; Committed: the block is already Completed
            }
            case "choice":
            {
                if (row.State == "Pending") { await SetBlock(row, "Running", null, now, ct); res.Changes++; }
                var cases = doc.Node["cases"] as JsonArray ?? new();
                var chosen = ChildRows(inst, row).FirstOrDefault(c => c.State != "Pending" && c.State != "Skipped");
                if (chosen is null)
                {
                    var unknowns = new List<string>(); DocBlock? pick = null;
                    for (var i = 0; i < cases.Count; i++)
                    {
                        var v = EvalBool(inst, (JsonObject)cases[i]!["when"]!, row, now);
                        if (v.Value == true) { pick = doc.Children[i]; break; }
                        if (v.Value is null) unknowns.AddRange(v.Unknowns);
                    }
                    if (pick is null && unknowns.Count > 0) { if (row.State != "Held") { await SetBlock(row, "Held", null, now, ct); res.Changes++; } return; }
                    if (pick is null && doc.Node["else"] is not null) pick = doc.Children[^1];
                    foreach (var childDoc in doc.Children)
                    {
                        var child = RowOf(inst, childDoc, row, row.IterationKey, row.Pass);
                        if (child is null) continue;
                        if (childDoc == pick) { chosen = child; }
                        else if (child.State == "Pending") { await SkipSubtree(inst, child, "NotApplicable", now, ct); res.Changes++; }
                    }
                    if (pick is null) { await SetBlock(row, "Completed", "NotApplicable", now, ct); res.Changes++; return; }
                    if (row.State == "Held") { await SetBlock(row, "Running", null, now, ct); res.Changes++; }
                    inst = await LoadAsync(inst.EntityId, ct); chosen = inst.Rows.First(r => r.EntityId == chosen!.EntityId);
                }
                var chosenDoc = doc.Children.First(c => c.Path == chosen.Path && c.Kind == chosen.Kind);
                if (!chosen.Terminal) { await ProcessAsync(inst, chosenDoc, chosen, now, res, ct); return; }
                await SetBlock(row, "Completed", chosen.Outcome ?? "Done", now, ct); res.Changes++;
                return;
            }
            case "parallel":
            {
                if (row.State == "Pending")
                {
                    await SetBlock(row, "Running", null, now, ct); res.Changes++;
                    var branches = doc.Node["branches"] as JsonArray ?? new();
                    for (var i = 0; i < branches.Count; i++)
                    {
                        var br = RowOf(inst, doc.Children[i], row, row.IterationKey, row.Pass);
                        if (br is null) continue;
                        if (branches[i]!["applies"] is JsonObject ap)
                        {
                            var v = EvalBool(inst, ap, row, now);
                            if (v.Value == false) { await SkipSubtree(inst, br, "NotApplicable", now, ct); continue; }
                            if (v.Value is null) { await SetBlock(br, "Held", null, now, ct); continue; }
                        }
                        await SetBlock(br, "Running", null, now, ct);
                    }
                    inst = await LoadAsync(inst.EntityId, ct); row = inst.Rows.First(r => r.EntityId == row.EntityId);
                }
                var kids = ChildRows(inst, row).ToList();
                foreach (var br in kids)
                {
                    var brDoc = doc.Children.First(c => c.Path == br.Path && c.Kind == br.Kind);
                    if (br.State == "Held" && brDoc.Node["applies"] is JsonObject ap2)
                    {
                        var v = EvalBool(inst, ap2, row, now);
                        if (v.Value == false) { await SkipSubtree(inst, br, "NotApplicable", now, ct); res.Changes++; continue; }
                        if (v.Value == true) { await SetBlock(br, "Running", null, now, ct); res.Changes++; }
                        continue;
                    }
                    if (!br.Terminal && br.State == "Running") await ProcessAsync(inst, brDoc, br, now, res, ct);
                }
                var latest = (await LoadRowsAsync(inst.EntityId, ct)).Where(r => r.ParentEntityId == row.EntityId).ToList();
                if (Joined(doc.Node["join"], latest.Count, latest.Count(r => r.Terminal), latest.Count(r => r.State == "Completed")))
                {
                    foreach (var other in latest.Where(r => !r.Terminal)) await SkipSubtree(inst, other, "Cancelled", now, ct);
                    await SetBlock(row, "Completed", "Done", now, ct); res.Changes++;
                }
                return;
            }
            case "branch":
            {
                var body = ChildRows(inst, row).FirstOrDefault();
                if (body is null) return;
                if (!body.Terminal) { await ProcessAsync(inst, doc.Children[0], body, now, res, ct); return; }
                await SetBlock(row, "Completed", body.Outcome ?? "Done", now, ct); res.Changes++;
                return;
            }
            case "foreach":
            {
                var bodyDoc = doc.Children[0];
                if (row.State is "Pending" or "Held")
                {
                    var over = Eval(inst, (JsonObject)doc.Node["over"]!, row, now);
                    if (over.Value is not List<object> members)
                    {
                        if (row.State != "Held") { await SetBlock(row, "Held", null, now, ct); res.Changes++; res.Notes.Add($"foreach {doc.Id}: set unknown ({string.Join(", ", over.Unknowns)})"); }
                        return;
                    }
                    await SetBlock(row, "Running", null, now, ct); res.Changes++;
                    var kind = doc.Node["subjectKind"]?.GetValue<string>() ?? "Any";
                    foreach (var m in members)
                    {
                        var id = m is Ref r ? r.Id : m.ToString()!;
                        if (!Guid.TryParse(id, out var mid)) continue;
                        var mat = await Exec("MaterialiseBlock", new JsonObject
                        {
                            ["ProcedureInstanceEntityId"] = inst.EntityId.ToString(), ["BlockPath"] = bodyDoc.Path, ["BlockKind"] = bodyDoc.Kind, ["ParentBlockInstanceEntityId"] = row.EntityId.ToString(),
                            ["IterationKey"] = mid.ToString().ToLowerInvariant(), ["Pass"] = row.Pass, ["MemberSubjectKind"] = kind, ["MemberSubjectEntityId"] = mid.ToString(), ["IncludeRoot"] = true,
                        }, ct);
                    }
                    if (members.Count == 0) { await SetBlock(row, "Completed", "Done", now, ct); return; }
                    inst = await LoadAsync(inst.EntityId, ct); row = inst.Rows.First(r => r.EntityId == row.EntityId);
                }
                var serial = doc.Node["concurrency"]?.GetValue<string>() == "serial";
                foreach (var m in ChildRows(inst, row))
                {
                    if (m.Terminal) continue;
                    await ProcessAsync(inst, bodyDoc, m, now, res, ct);
                    if (serial) break;
                }
                var latest = (await LoadRowsAsync(inst.EntityId, ct)).Where(r => r.ParentEntityId == row.EntityId).ToList();
                if (latest.Count > 0 && Joined(doc.Node["join"], latest.Count, latest.Count(r => r.Terminal), latest.Count(r => r.State == "Completed")))
                {
                    foreach (var other in latest.Where(r => !r.Terminal)) await SkipSubtree(inst, other, "Cancelled", now, ct);
                    await SetBlock(row, "Completed", "Done", now, ct); res.Changes++;
                }
                return;
            }
            case "repeat":
            {
                var bodyDoc = doc.Children[0];
                var passes = ChildRows(inst, row).ToList();
                if (row.State == "Pending" || passes.Count == 0)
                {
                    await SetBlock(row, "Running", null, now, ct);
                    await Exec("MaterialiseBlock", new JsonObject { ["ProcedureInstanceEntityId"] = inst.EntityId.ToString(), ["BlockPath"] = bodyDoc.Path, ["BlockKind"] = bodyDoc.Kind, ["ParentBlockInstanceEntityId"] = row.EntityId.ToString(), ["IterationKey"] = row.IterationKey, ["Pass"] = 1, ["MemberSubjectKind"] = row.MemberKind, ["MemberSubjectEntityId"] = row.MemberId?.ToString(), ["IncludeRoot"] = true }, ct);
                    res.Changes++;
                    inst = await LoadAsync(inst.EntityId, ct); row = inst.Rows.First(r => r.EntityId == row.EntityId); passes = ChildRows(inst, row).ToList();
                }
                var current = passes.OrderByDescending(p => p.Pass).First();
                if (!current.Terminal) { await ProcessAsync(inst, bodyDoc, current, now, res, ct); return; }
                var until = EvalBool(inst, (JsonObject)doc.Node["until"]!, current, now);
                if (until.Value == true) { await SetBlock(row, "Completed", "Done", now, ct); res.Changes++; return; }
                var max = doc.Node["max"]?.GetValue<int>() ?? int.MaxValue;
                if (until.Value == false && current.Pass < max)
                {
                    await Exec("MaterialiseBlock", new JsonObject { ["ProcedureInstanceEntityId"] = inst.EntityId.ToString(), ["BlockPath"] = bodyDoc.Path, ["BlockKind"] = bodyDoc.Kind, ["ParentBlockInstanceEntityId"] = row.EntityId.ToString(), ["IterationKey"] = row.IterationKey, ["Pass"] = current.Pass + 1, ["MemberSubjectKind"] = row.MemberKind, ["MemberSubjectEntityId"] = row.MemberId?.ToString(), ["IncludeRoot"] = true }, ct);
                    if (row.State == "Held") await SetBlock(row, "Running", null, now, ct);
                    res.Changes++; res.Notes.Add($"repeat {doc.Id}: pass {current.Pass + 1}");
                    return;
                }
                if (row.State != "Held") { await SetBlock(row, "Held", null, now, ct); res.Changes++; res.Notes.Add($"repeat {doc.Id}: held ({(until.Value is null ? "until unknown: " + string.Join(", ", until.Unknowns) : "max passes reached")})"); }
                return;
            }
            case "call":
            {
                if (row.State == "Pending")
                {
                    await SetBlock(row, "Running", null, now, ct);
                    var key = doc.Node["procedure"]!.GetValue<string>();
                    var (member, memberKind, _) = Scope(inst, row);
                    Guid subject = member ?? inst.SubjectEntityId; var subjectKind = member is not null ? memberKind ?? "Any" : inst.SubjectKind;
                    if (doc.Node["subject"] is JsonObject sx)
                    {
                        var sv = Eval(inst, sx, row, now);
                        if (sv.Value is Ref sr && Guid.TryParse(sr.Id, out var sg)) { subject = sg; subjectKind = sr.Kind; }
                        else { await SetBlock(row, "Held", null, now, ct); res.Notes.Add($"call {doc.Id}: subject unknown"); return; }
                    }
                    var started = await Exec("StartProcedure", new JsonObject
                    {
                        ["ProcedureKey"] = key, ["SubjectKind"] = subjectKind, ["SubjectEntityId"] = subject.ToString(), ["WorkflowInstanceEntityId"] = inst.WorkflowInstanceEntityId?.ToString(),
                        ["WorkRequestEntityId"] = inst.WorkRequestEntityId?.ToString(), ["ParentInstanceEntityId"] = inst.EntityId.ToString(), ["CallBlockPath"] = doc.Path,
                    }, ct);
                    res.Changes++; res.Notes.Add($"call {doc.Id}: {key} started");
                    if (Guid.TryParse(started["EntityId"]?.GetValue<string>(), out var childId)) await AdvanceAsync(childId, now, ct);
                    return;
                }
                // a running call: the child run is advanced with its parent (its completion marks this block, CompleteInstance)
                if (row.State == "Running")
                {
                    var child = await session.ScalarAsync<Guid?>("SELECT TOP (1) EntityId FROM process.vProcedureInstance WHERE ParentInstanceEntityId = @p AND CallBlockPath = @c AND State IN (N'Running', N'Held') ORDER BY StartedAt DESC",
                        new Dictionary<string, object?> { ["@p"] = inst.EntityId, ["@c"] = doc.Path }, ct);
                    if (child is { } cid) { var r = await AdvanceAsync(cid, now, ct); res.Changes += r.Changes; }
                }
                return;
            }
            case "hold":
            {
                if (row.State == "Pending")
                {
                    await Exec("OpenHold", new JsonObject { ["BlockInstanceEntityId"] = row.EntityId.ToString(), ["Reason"] = doc.Node["reason"]?.GetValue<string>() ?? "other", ["At"] = now }, ct);
                    res.Changes++;
                    inst = await LoadAsync(inst.EntityId, ct); row = inst.Rows.First(r => r.EntityId == row.EntityId);
                }
                if (row.State == "Held")
                {
                    if (doc.Node["until"] is JsonObject u)
                    {
                        var v = EvalBool(inst, u, row, now);
                        if (v.Value == true) { await Exec("ReleaseHold", new JsonObject { ["BlockInstanceEntityId"] = row.EntityId.ToString(), ["ReleaseBasis"] = "Condition", ["At"] = now }, ct); res.Changes++; return; }
                    }
                    if (doc.Node["maxDuration"]?.GetValue<string>() is { } md && row.StartedAt is { } started && ParseDuration(md) is { } dur && Values.AddDuration(started, dur) <= now)
                    {
                        await Exec("ReleaseHold", new JsonObject { ["BlockInstanceEntityId"] = row.EntityId.ToString(), ["ReleaseBasis"] = "Expired", ["Reason"] = $"past maxDuration {md}", ["At"] = now }, ct);
                        res.Changes++; res.Notes.Add($"hold {doc.Id}: expired");
                    }
                }
                return;
            }
        }
    }

    /// <summary>A duration literal in text form (procedure.schema.json: "180 d", "30 min", "2 w").</summary>
    public static Duration? ParseDuration(string text)
    {
        var m = System.Text.RegularExpressions.Regex.Match(text.Trim(), @"^([0-9]+) ?(min|h|d|w|mo|y)$");
        return m.Success ? new Duration(decimal.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture), m.Groups[2].Value) : null;
    }

    private static bool Joined(JsonNode? join, int total, int terminal, int completed)
    {
        if (join is JsonValue jv && jv.TryGetValue<int>(out var n)) return completed >= n;
        var j = join?.GetValue<string>() ?? "all";
        return j == "any" ? completed >= 1 : terminal >= total;
    }

    /// <summary>Ends a scope (a foreach member's body, a parallel branch) with a branch outcome (§3, #51): remaining steps are Skipped with that reason and the scope completes with it; the join counts it as complete.</summary>
    public async Task EndScopeAsync(Guid instanceId, Guid stepInstanceId, string outcome, DateTimeOffset now, CancellationToken ct)
    {
        var inst = await LoadAsync(instanceId, ct);
        var stepRow = inst.Rows.First(r => r.StepEntityId == stepInstanceId);
        BlockRow? scope = null; var r = stepRow;
        while (r is not null)
        {
            var parent = r.ParentEntityId is null ? null : inst.Rows.FirstOrDefault(x => x.EntityId == r.ParentEntityId);
            if (parent is not null && (parent.Kind == "foreach" || parent.Kind == "parallel")) { scope = r; break; }
            r = parent;
        }
        scope ??= inst.Rows.First(x => x.ParentEntityId is null);
        await SkipSubtree(inst, scope, outcome, now, ct, keepCommitted: true);
    }

    private async Task SkipSubtree(Instance inst, BlockRow top, string outcome, DateTimeOffset now, CancellationToken ct, bool keepCommitted = true)
    {
        var rows = await LoadRowsAsync(inst.EntityId, ct);
        var ids = new HashSet<Guid> { top.EntityId };
        bool grew;
        do { grew = false; foreach (var x in rows) if (x.ParentEntityId is not null && ids.Contains(x.ParentEntityId.Value) && ids.Add(x.EntityId)) grew = true; } while (grew);
        foreach (var x in rows.Where(x => ids.Contains(x.EntityId) && x.EntityId != top.EntityId && !x.Terminal))
        {
            if (x.StepEntityId is not null && x.StepState is not ("Committed" or "Skipped" or "Varied"))
                await Exec("SetStepState", new JsonObject { ["EntityId"] = x.StepEntityId.ToString(), ["State"] = "Skipped", ["Outcome"] = outcome }, ct);
            else if (x.StepEntityId is null)
                await Exec("SetBlockState", new JsonObject { ["EntityId"] = x.EntityId.ToString(), ["State"] = "Skipped", ["Outcome"] = outcome, ["At"] = now }, ct);
        }
        var topNow = rows.First(x => x.EntityId == top.EntityId);
        if (!topNow.Terminal)
        {
            if (topNow.StepEntityId is not null && topNow.StepState is not ("Committed" or "Skipped" or "Varied"))
                await Exec("SetStepState", new JsonObject { ["EntityId"] = topNow.StepEntityId.ToString(), ["State"] = "Skipped", ["Outcome"] = outcome }, ct);
            else if (topNow.StepEntityId is null)
                await Exec("SetBlockState", new JsonObject { ["EntityId"] = top.EntityId.ToString(), ["State"] = outcome is "NotApplicable" or "Cancelled" ? "Skipped" : "Completed", ["Outcome"] = outcome, ["At"] = now }, ct);
        }
    }

    // ------------------------------------------------------------------ due dates (§3 due, #44: derived on read)
    public (DateTimeOffset? at, string basis) Due(Instance inst, DocBlock stepDoc, BlockRow row, DateTimeOffset now)
    {
        if (stepDoc.Node["due"] is not JsonObject due || due["cadence"] is not JsonObject cadence) return (null, "None");
        var anchorId = due["anchor"]?.GetValue<string>();
        var (member, _, pass) = Scope(inst, row);
        var anchor = inst.Rows.Where(r => r.StepId == anchorId && r.CommittedAt is not null)
            .Where(r => member is null || Scope(inst, r).member == member)
            .OrderByDescending(r => r.Pass).ThenByDescending(r => r.CommittedAt).FirstOrDefault();
        if (anchor?.CommittedAt is null) return (null, "AnchorUnknown");
        var env = new Dictionary<string, object>(StringComparer.Ordinal) { ["event"] = anchor.CommittedAt.Value, ["effective"] = anchor.CommittedAt.Value };
        var r = Eval(inst, cadence, row, now, env);
        return r.Value is DateTimeOffset d ? (d, "Cadence") : (null, "Unknown");
    }

    // ------------------------------------------------------------------ writes
    private Task SetBlock(BlockRow row, string state, string? outcome, DateTimeOffset now, CancellationToken ct)
        => Exec("SetBlockState", new JsonObject { ["EntityId"] = row.EntityId.ToString(), ["State"] = state, ["Outcome"] = outcome, ["At"] = now }, ct);

    private Task SetStep(BlockRow row, string state, string? heldReason, CancellationToken ct)
        => Exec("SetStepState", new JsonObject { ["EntityId"] = row.StepEntityId!.Value.ToString(), ["State"] = state, ["HeldReason"] = heldReason }, ct);

    public async Task<JsonObject> Exec(string procedure, JsonObject args, CancellationToken ct)
    {
        var proc = catalog.Procedure("process", procedure) ?? throw new ApiException(500, "internal", $"process.{procedure} is not in the catalogue.");
        foreach (var k in args.Where(kv => kv.Value is null).Select(kv => kv.Key).ToList()) args.Remove(k);
        return await session.ExecuteProcedureAsync(proc, args, ct);
    }
}
