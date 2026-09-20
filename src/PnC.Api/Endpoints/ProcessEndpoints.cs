using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Engine;
using PnC.Api.Security;
using PnC.Formula;

namespace PnC.Api.Endpoints;

// docs/design/API.md §8b (W4). The procedure engine's endpoints: what the generic dispatcher cannot do because an
// expression must be evaluated (guards, preconditions, validations, competency) or a run must be advanced afterwards.
// Every write is a process.* procedure (decision #106); permissions are the map's for that procedure, decided on the
// work request the run belongs to (a scoped engineer's grant covers the request's scope).
//   POST process/workflows/start                              StartWorkflow, then the started run is advanced
//   POST process/workflow-instances/{id}/transitions          a person's transition (when-guards evaluated here)
//   GET  process/procedure-instances/{id}                     the tree, ready steps, due dates
//   POST process/procedure-instances/{id}/evaluate            re-evaluate and advance now (§4.1 "a person may force")
//   GET  process/step-instances/{id}/draft                    the draft (a read by anyone but the claimant is logged, #68)
//   POST process/step-instances/{id}/claim|release|takeover|draft|witness|commit|checkin
//   POST process/block-instances/{id}/release-hold            a person releases a hold with a reason
//   POST process/sweep                                        run the sweep now (Administrator)

public static class ProcessEndpoints
{
    public static void Map(WebApplication app, Catalog catalog, PermissionMap map, AuthorizationService authz, string connectionString)
    {
        var log = app.Logger;

        async Task Require(HttpContext http, string schema, string proc, string? subjectKind, Guid? subject, CancellationToken ct)
        {
            var code = map.ForProcedure(schema, proc) ?? throw new ApiException(404, "not_callable", $"{schema}.{proc} is not callable over the API.");
            await authz.RequireAsync(http.Session(), http.User(), code, subjectKind, subject, $"POST {schema}.{proc}", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
        }
        async Task<JsonObject> Exec(HttpContext http, string proc, JsonObject args, CancellationToken ct)
        {
            var p = catalog.Procedure("process", proc) ?? throw new ApiException(500, "internal", $"process.{proc} is not in the catalogue.");
            foreach (var k in args.Where(kv => kv.Value is null).Select(kv => kv.Key).ToList()) args.Remove(k);
            return await http.Session().ExecuteProcedureAsync(p, args, ct);
        }
        Interpreter Interp(HttpContext http) => new(http.Session(), catalog, log);

        // ---- workflows
        app.MapPost("/api/v1/process/workflows/start", async (HttpContext http, CancellationToken ct) =>
        {
            var body = await ReadObject(http, ct);
            var subjectKind = body["subjectKind"]?.GetValue<string>() ?? throw new ApiException(400, "bad_request", "subjectKind is required.");
            var subject = Guid.TryParse(body["subjectEntityId"]?.ToString(), out var g) ? g : throw new ApiException(400, "bad_request", "subjectEntityId is required.");
            await Require(http, "process", "StartWorkflow", subjectKind, subject, ct);
            var r = await Exec(http, "StartWorkflow", new JsonObject
            {
                ["WorkflowKey"] = body["workflowKey"]?.GetValue<string>() ?? throw new ApiException(400, "bad_request", "workflowKey is required."),
                ["SubjectKind"] = subjectKind, ["SubjectEntityId"] = subject.ToString(), ["Inputs"] = body["inputs"]?.DeepClone(),
            }, ct);
            var wf = Guid.Parse(r["EntityId"]!.GetValue<string>());
            var started = await StartedRuns(http.Session(), wf, ct);
            var interp = Interp(http);
            foreach (var pi in started) await interp.AdvanceAsync(pi, await http.Session().NowAsync(ct), ct);
            return Results.Json(new { workflowInstanceEntityId = wf, procedureInstances = started });
        });

        app.MapPost("/api/v1/process/workflow-instances/{id:guid}/transitions", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var body = await ReadObject(http, ct);
            var name = body["name"]?.GetValue<string>() ?? throw new ApiException(400, "bad_request", "name is required.");
            var wf = await WorkflowHead(http.Session(), id, ct);
            await Require(http, "process", "Transition", "WorkRequest", wf.WorkRequest ?? (wf.SubjectKind == "WorkRequest" ? wf.Subject : null), ct);
            var guards = GuardVerdicts(http.Session(), wf, name, await http.Session().NowAsync(ct));
            var r = await Exec(http, "Transition", new JsonObject
            {
                ["WorkflowInstanceEntityId"] = id.ToString(), ["TransitionName"] = name, ["Reason"] = body["reason"]?.DeepClone(), ["GuardEvaluation"] = guards,
                ["OverrideReason"] = body["overrideReason"]?.DeepClone(), ["OverrideApprovedByActorId"] = body["overrideApprovedByActorId"]?.DeepClone(),
            }, ct);
            var interp = Interp(http);
            foreach (var pi in await StartedRuns(http.Session(), id, ct)) await interp.AdvanceAsync(pi, await http.Session().NowAsync(ct), ct);
            await ComplianceTriggers.RequestForWorkAsync(http.Session(), catalog, wf.SubjectKind, wf.Subject, wf.WorkRequest, $"process.Transition {name}", log, ct);   // #214
            return Results.Json(new { workflowInstanceEntityId = id, transition = name, toState = r["ToState"], transitionId = r["TransitionId"] });
        });

        // ---- procedure instances
        app.MapGet("/api/v1/process/procedure-instances/{id:guid}", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var interp = Interp(http);
            var inst = await interp.LoadAsync(id, ct);
            await authz.RequireAsync(s, u, map.ForView("process", "vProcedureInstanceTree") ?? "WorkRequest.Read", "WorkRequest", inst.WorkRequestEntityId, $"GET process.vProcedureInstanceTree", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var now = await http.Session().NowAsync(ct);
            var docByKey = new Dictionary<(string, string), DocBlock>();
            void Index(DocBlock b) { docByKey[(b.Path, b.Kind)] = b; foreach (var c in b.Children) Index(c); }
            Index(inst.Root);
            var blocks = inst.Rows.Select(r =>
            {
                docByKey.TryGetValue((r.Path, r.Kind), out var d);
                (DateTimeOffset? at, string basis) due = r.StepEntityId is not null && d is not null && d.Node["due"] is not null ? interp.Due(inst, d, r, now) : (null, "None");
                return new
                {
                    blockInstanceEntityId = r.EntityId, parent = r.ParentEntityId, path = r.Path, kind = r.Kind, iterationKey = r.IterationKey, pass = r.Pass,
                    memberSubjectKind = r.MemberKind, memberSubjectEntityId = r.MemberId, state = r.State, outcome = r.Outcome, startedAt = r.StartedAt, completedAt = r.CompletedAt,
                    title = d?.Node["title"]?.GetValue<string>(),
                    step = r.StepEntityId is null ? null : new { stepInstanceEntityId = r.StepEntityId, stepId = r.StepId, state = r.StepState, outcome = r.StepOutcome, committedAt = r.CommittedAt, heldReason = r.HeldReason, role = d?.Node["role"]?.GetValue<string>(), dueAt = due.at, dueBasis = due.basis },
                };
            });
            return Results.Json(new
            {
                procedureInstanceEntityId = inst.EntityId, versionRowId = inst.VersionRowId, key = inst.Document["key"], subjectKind = inst.SubjectKind, subjectEntityId = inst.SubjectEntityId,
                workRequestEntityId = inst.WorkRequestEntityId, workflowInstanceEntityId = inst.WorkflowInstanceEntityId, state = inst.State, outcome = inst.Outcome, produced = inst.Produced,
                readySteps = inst.Rows.Where(r => r.StepState is "Ready" or "Active").Select(r => new { r.StepEntityId, r.StepId, r.StepState, member = r.MemberId }),
                blocks,
            });
        });

        app.MapPost("/api/v1/process/procedure-instances/{id:guid}/evaluate", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var interp = Interp(http);
            var inst = await interp.LoadAsync(id, ct);
            await Require(http, "process", "SetBlockState", "WorkRequest", inst.WorkRequestEntityId, ct);
            var r = await interp.AdvanceAsync(id, await http.Session().NowAsync(ct), ct);
            return Results.Json(new { procedureInstanceEntityId = id, r.Changes, r.Completed, r.Notes });
        });

        // ---- steps
        async Task<(Guid instance, Guid? wr, Guid? claimant)> StepHead(SqlSession s, Guid stepId, CancellationToken ct)
        {
            var row = (await s.RowsAsync("""
                SELECT b.ProcedureInstanceEntityId, i.WorkRequestEntityId, st.ClaimedByActorId
                FROM process.vStepInstance st JOIN process.vBlockInstance b ON b.EntityId = st.BlockInstanceEntityId JOIN process.vProcedureInstance i ON i.EntityId = b.ProcedureInstanceEntityId
                WHERE st.EntityId = @s
                """, new Dictionary<string, object?> { ["@s"] = stepId }, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_step", "No step instance has that id.");
            return (Guid.Parse(row["ProcedureInstanceEntityId"]!.GetValue<string>()), G(row["WorkRequestEntityId"]), G(row["ClaimedByActorId"]));
        }

        // #165: one read for the generic step screen — the step's live state and claim, its draft, and its definition node lifted
        // from the pinned document (title, instruction, capture fields, evidence, outcomes, sign-off), so no screen is coded per step.
        app.MapGet("/api/v1/process/step-instances/{id:guid}", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var (instanceId, wr, claimant) = await StepHead(s, id, ct);
            await authz.RequireAsync(s, u, map.ForView("process", "vStepInstance") ?? "WorkRequest.Read", "WorkRequest", wr, "GET process.vStepInstance", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var interp = Interp(http);
            var inst = await interp.LoadAsync(instanceId, ct);
            var row = inst.Rows.FirstOrDefault(r => r.StepEntityId == id) ?? throw new ApiException(404, "unknown_step", "No step instance has that id.");
            var doc = FindDoc(inst.Root, row.Path, "step") ?? throw new ApiException(500, "internal", $"The pinned document has no step at {row.Path}.");
            var node = doc.Node;
            var live = (await s.RowsAsync("""
                SELECT st.State, st.Outcome, st.AssignedRoleCode, st.ClaimedByActorId, st.ClaimedAt, st.ClaimExpiresAt, st.Draft, st.DraftModifiedAt,
                       st.CapturedAt, st.CapturedByActorId, st.CaptureSource, st.CommittedRecordEntityId, st.CommittedByActorId, st.WitnessedByActorId, st.CommittedAt, st.HeldReason,
                       cp.DisplayName AS ClaimedByDisplayName, wp.DisplayName AS WitnessedByDisplayName
                FROM process.vStepInstance st
                LEFT JOIN personnel.vActor ca ON ca.ActorId = st.ClaimedByActorId LEFT JOIN personnel.vPerson cp ON cp.EntityId = ca.PersonEntityId
                LEFT JOIN personnel.vActor wa ON wa.ActorId = st.WitnessedByActorId LEFT JOIN personnel.vPerson wp ON wp.EntityId = wa.PersonEntityId
                WHERE st.EntityId = @s
                """, new Dictionary<string, object?> { ["@s"] = id }, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_step", "No step instance has that id.");
            var mine = claimant is not null && await s.ScalarAsync<int>("SELECT CASE WHEN EXISTS (SELECT 1 FROM personnel.vActor a WHERE a.ActorId = @a AND a.PersonEntityId = @p) THEN 1 ELSE 0 END",
                new Dictionary<string, object?> { ["@a"] = claimant, ["@p"] = u.PersonEntityId }, ct) == 1;   // the scalar is an int (0/1), never a bit
            if (!mine && live["Draft"] is not null)   // #68: every read of a draft by anyone other than its claimant is audit-logged
                await s.ExecAsync("EXEC [audit].[LogRead] @SubjectSchema = N'process', @SubjectTable = N'StepInstance', @SubjectEntityId = @id", new Dictionary<string, object?> { ["@id"] = id }, ct);
            var now = await s.NowAsync(ct);
            (DateTimeOffset? at, string basis) due = node["due"] is not null ? interp.Due(inst, doc, row, now) : (null, "None");
            var alias = node["role"]?.GetValue<string>();
            var roleNode = alias is null ? null : inst.Document["roles"]?[alias] as JsonObject;
            var draftText = live["Draft"]?.GetValue<string>();
            return Results.Json(new
            {
                stepInstanceEntityId = id, procedureInstanceEntityId = instanceId, procedureKey = inst.Document["key"]?.DeepClone(), procedureVersionRowId = inst.VersionRowId,
                workRequestEntityId = wr, workflowInstanceEntityId = inst.WorkflowInstanceEntityId, subjectKind = inst.SubjectKind, subjectEntityId = inst.SubjectEntityId,
                blockPath = row.Path, stepId = row.StepId, state = live["State"]?.DeepClone(), outcome = live["Outcome"]?.DeepClone(), heldReason = live["HeldReason"]?.DeepClone(),
                memberSubjectKind = row.MemberKind, memberSubjectEntityId = row.MemberId,
                assignedRoleCode = live["AssignedRoleCode"]?.DeepClone(), claimedByActorId = claimant, claimedByDisplayName = live["ClaimedByDisplayName"]?.DeepClone(),
                claimedAt = live["ClaimedAt"]?.DeepClone(), claimExpiresAt = live["ClaimExpiresAt"]?.DeepClone(), isClaimant = mine,
                witnessedByActorId = live["WitnessedByActorId"]?.DeepClone(), witnessedByDisplayName = live["WitnessedByDisplayName"]?.DeepClone(),
                committedAt = live["CommittedAt"]?.DeepClone(), committedByActorId = live["CommittedByActorId"]?.DeepClone(), committedRecordEntityId = live["CommittedRecordEntityId"]?.DeepClone(),
                capturedAt = live["CapturedAt"]?.DeepClone(), captureSource = live["CaptureSource"]?.DeepClone(), draftModifiedAt = live["DraftModifiedAt"]?.DeepClone(),
                draft = draftText is null ? null : JsonNode.Parse(draftText), dueAt = due.at, dueBasis = due.basis,
                definition = new
                {
                    title = node["title"]?.DeepClone(), instruction = node["instruction"]?.DeepClone(), role = alias, roleCode = roleNode?["role"]?.DeepClone(), requires = roleNode?["requires"]?.DeepClone(),
                    capture = node["capture"]?.DeepClone(), outcomes = node["outcomes"]?.DeepClone() ?? new JsonArray("Done"), evidence = node["evidence"]?.DeepClone(), signoff = node["signoff"]?.DeepClone(),
                    deviation = node["deviation"]?.DeepClone(), due = node["due"]?.DeepClone(), record = node["record"]?.DeepClone(), produces = node["produces"]?.DeepClone(),
                    advances = node["advances"]?.DeepClone(), branchOutcome = node["branchOutcome"]?.DeepClone(), precondition = node["precondition"] is not null,
                },
            });
        });

        app.MapGet("/api/v1/process/step-instances/{id:guid}/draft", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var u = http.User(); var s = http.Session();
            var (_, wr, claimant) = await StepHead(s, id, ct);
            await authz.RequireAsync(s, u, map.ForView("process", "vStepInstance") ?? "WorkRequest.Read", "WorkRequest", wr, "GET process.vStepInstance", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var mine = claimant is not null && await s.ScalarAsync<int>("SELECT CASE WHEN EXISTS (SELECT 1 FROM personnel.vActor a WHERE a.ActorId = @a AND a.PersonEntityId = @p) THEN 1 ELSE 0 END",
                new Dictionary<string, object?> { ["@a"] = claimant, ["@p"] = u.PersonEntityId }, ct) == 1;   // the scalar is an int (0/1), never a bit
            if (!mine)   // #68: every read of a draft by anyone other than its claimant is audit-logged
                await s.ExecAsync("EXEC [audit].[LogRead] @SubjectSchema = N'process', @SubjectTable = N'StepInstance', @SubjectEntityId = @id", new Dictionary<string, object?> { ["@id"] = id }, ct);
            var draft = await s.ScalarAsync<string>("SELECT Draft FROM process.vStepInstance WHERE EntityId = @s", new Dictionary<string, object?> { ["@s"] = id }, ct);
            return Results.Json(new { stepInstanceEntityId = id, claimedByActorId = claimant, isClaimant = mine, draft = draft is null ? null : JsonNode.Parse(draft) });
        });

        foreach (var (action, proc) in new[] { ("claim", "ClaimStep"), ("release", "ReleaseStep"), ("takeover", "TakeOverStep"), ("witness", "WitnessStep") })
        {
            app.MapPost($"/api/v1/process/step-instances/{{id:guid}}/{action}", async (Guid id, HttpContext http, CancellationToken ct) =>
            {
                var body = await ReadObject(http, ct);
                var (_, wr, _) = await StepHead(http.Session(), id, ct);
                await Require(http, "process", proc, "WorkRequest", wr, ct);
                var args = new JsonObject { ["StepInstanceEntityId"] = id.ToString() };
                if (proc == "TakeOverStep") args["Reason"] = body["reason"]?.DeepClone();
                await Exec(http, proc, args, ct);
                return Results.Json(new { stepInstanceEntityId = id, action });
            });
        }

        app.MapPost("/api/v1/process/step-instances/{id:guid}/draft", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var body = await ReadObject(http, ct);
            var (_, wr, _) = await StepHead(http.Session(), id, ct);
            await Require(http, "process", "SaveDraft", "WorkRequest", wr, ct);
            await Exec(http, "SaveDraft", new JsonObject { ["StepInstanceEntityId"] = id.ToString(), ["Draft"] = (body["draft"] ?? new JsonObject()).DeepClone() }, ct);
            return Results.Json(new { stepInstanceEntityId = id, saved = true });
        });

        async Task<IResult> CommitAsync(Guid id, HttpContext http, bool deferred, CancellationToken ct)
        {
            var body = await ReadObject(http, ct);
            var u = http.User(); var s = http.Session();
            var (instanceId, wr, _) = await StepHead(s, id, ct);
            await Require(http, "process", "CommitStep", "WorkRequest", wr, ct);
            var interp = Interp(http);
            var inst = await interp.LoadAsync(instanceId, ct);
            var row = inst.Rows.First(r => r.StepEntityId == id);
            var stepDoc = FindDoc(inst.Root, row.Path, "step") ?? throw new ApiException(500, "internal", "The step is not in the pinned document.");
            var now = await http.Session().NowAsync(ct);

            // §5.2: the technician who captured, resolved from their user principal name (identification; the pack's own attestation arrives with FR-7.1)
            Guid? capturedBy = null; Guid? capturedPerson = null; DateTimeOffset? capturedAt = null;
            if (deferred)
            {
                var upn = body["capturedBy"]?.GetValue<string>() ?? throw new ApiException(400, "bad_request", "capturedBy (the technician's user principal name) is required for a check-in.");
                var who = (await s.RowsAsync("SELECT TOP (1) a.ActorId, a.PersonEntityId FROM security.vUser us JOIN personnel.vActor a ON a.PersonEntityId = us.PersonEntityId WHERE us.UserPrincipalName = @u AND us.IsEnabled = 1 ORDER BY a.ActorId",
                    new Dictionary<string, object?> { ["@u"] = upn }, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(400, "bad_request", $"{upn} is not an enabled platform user.");
                capturedBy = Guid.Parse(who["ActorId"]!.GetValue<string>()); capturedPerson = Guid.Parse(who["PersonEntityId"]!.GetValue<string>());
                capturedAt = DateTimeOffset.TryParse(body["capturedAt"]?.GetValue<string>(), out var ca) ? ca : throw new ApiException(400, "bad_request", "capturedAt (the device clock instant) is required for a check-in.");
            }
            var committerPerson = capturedPerson ?? u.PersonEntityId;

            // 3 validation: every capture field's validate with value bound
            var capture = body["capture"] as JsonObject;
            var validationOk = true; var unknowns = new List<string>();
            if (stepDoc.Node["capture"] is JsonObject cap && capture is not null)
                foreach (var (field, vtNode) in cap)
                {
                    var vt = (JsonObject)vtNode!;
                    if (vt["validate"] is not JsonObject validate || capture[field] is null) continue;
                    var env = new Dictionary<string, object>(StringComparer.Ordinal) { ["value"] = DbFactReader.Typed(capture[field]!, vt) };
                    var v = interp.EvalBool(inst, validate, row, now, env);
                    if (v.Value != true) { validationOk = false; unknowns.AddRange(v.Unknowns.Select(x => $"{field}: {x}")); if (v.Value == false) unknowns.Add($"{field}: false"); }
                }
            // 4 competency: the role alias's requires for the committing person
            var competencyOk = true;
            var alias = stepDoc.Node["role"]?.GetValue<string>();
            if (alias is not null && inst.Document["roles"]?[alias]?["requires"] is JsonObject req)
            {
                var reader = new DbFactReader(s.Connection, null);
                var r = Evaluator.Evaluate(req, reader, new Ref(committerPerson.ToString(), "Person"), now);
                competencyOk = r.Value is true;
                if (!competencyOk) unknowns.AddRange(r.Unknowns.Select(x => "competency: " + x));
            }

            var result = await Exec(http, "CommitStep", new JsonObject
            {
                ["StepInstanceEntityId"] = id.ToString(), ["Outcome"] = body["outcome"]?.DeepClone(), ["Capture"] = capture?.DeepClone(), ["Evidence"] = body["evidence"]?.DeepClone(),
                ["ValidationOk"] = validationOk, ["ValidationUnknowns"] = unknowns.Count == 0 ? null : string.Join("; ", unknowns), ["CompetencyOk"] = competencyOk,
                ["OverrideReason"] = body["overrideReason"]?.DeepClone(), ["OverrideApprovedByActorId"] = body["overrideApprovedByActorId"]?.DeepClone(),
                ["CapturedByActorId"] = capturedBy?.ToString(), ["CapturedAt"] = capturedAt, ["CaptureTimeQuality"] = deferred ? 2 : null, ["At"] = now,
            }, ct);

            // 12 advances: the declared transition on the produced entity's lifecycle, its when-guards evaluated here
            string? advanced = null;
            var outcome = body["outcome"]?.GetValue<string>() ?? "Done";
            var onOutcome = stepDoc.Node["advances"]?["onOutcome"]?.GetValue<string>();
            if (result["AdvancesWorkflowKey"]?.GetValue<string>() is { } wfKey && (onOutcome is null || onOutcome == outcome))
            {
                var subj = Guid.Parse(result["AdvancesSubjectEntityId"]!.GetValue<string>());
                var wf = await WorkflowFor(s, wfKey, subj, ct) ?? throw new ApiException(409, "rule", $"No running {wfKey} instance governs the subject the step advances.");
                var tname = result["AdvancesTransition"]!.GetValue<string>();
                var guards = GuardVerdicts(s, wf, tname, now);
                var tr = await Exec(http, "Transition", new JsonObject { ["WorkflowInstanceEntityId"] = wf.EntityId.ToString(), ["TransitionName"] = tname, ["GuardEvaluation"] = guards, ["FiredByStepInstanceEntityId"] = id.ToString(), ["At"] = now,
                    ["OverrideReason"] = body["overrideReason"]?.DeepClone(), ["OverrideApprovedByActorId"] = body["overrideApprovedByActorId"]?.DeepClone() }, ct);
                advanced = $"{wfKey}.{tname} → {tr["ToState"]}";
            }
            // 11 branch outcome: the enclosing member or branch ends with it
            if (result["BranchOutcome"]?.GetValue<string>() is { } bo) await interp.EndScopeAsync(instanceId, id, bo, now, ct);
            var adv = await interp.AdvanceAsync(instanceId, now, ct);
            // #214: a step over a device may have put settings in service or written what a rule reads — the worker re-evaluates it
            await ComplianceTriggers.RequestForWorkAsync(s, catalog, inst.SubjectKind, inst.SubjectEntityId, inst.WorkRequestEntityId ?? wr, $"process.CommitStep {row.Path}", log, ct);
            return Results.Json(new
            {
                stepInstanceEntityId = id, outcome, recordEntityId = result["RecordEntityId"], producedEntityId = result["ProducedEntityId"], branchOutcome = result["BranchOutcome"],
                advanced, deferred, instance = new { adv.Changes, adv.Completed, adv.Notes },
            });
        }
        app.MapPost("/api/v1/process/step-instances/{id:guid}/commit", (Guid id, HttpContext http, CancellationToken ct) => CommitAsync(id, http, false, ct));
        app.MapPost("/api/v1/process/step-instances/{id:guid}/checkin", (Guid id, HttpContext http, CancellationToken ct) => CommitAsync(id, http, true, ct));

        app.MapPost("/api/v1/process/block-instances/{id:guid}/release-hold", async (Guid id, HttpContext http, CancellationToken ct) =>
        {
            var body = await ReadObject(http, ct);
            var head = (await http.Session().RowsAsync("SELECT b.ProcedureInstanceEntityId, i.WorkRequestEntityId FROM process.vBlockInstance b JOIN process.vProcedureInstance i ON i.EntityId = b.ProcedureInstanceEntityId WHERE b.EntityId = @b",
                new Dictionary<string, object?> { ["@b"] = id }, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_block", "No block instance has that id.");
            await Require(http, "process", "ReleaseHold", "WorkRequest", G(head["WorkRequestEntityId"]), ct);
            await Exec(http, "ReleaseHold", new JsonObject { ["BlockInstanceEntityId"] = id.ToString(), ["ReleaseBasis"] = "Manual", ["Reason"] = body["reason"]?.DeepClone() }, ct);
            var adv = await Interp(http).AdvanceAsync(Guid.Parse(head["ProcedureInstanceEntityId"]!.GetValue<string>()), await http.Session().NowAsync(ct), ct);
            return Results.Json(new { blockInstanceEntityId = id, released = true, instance = new { adv.Changes, adv.Completed } });
        });

        // ---- the sweep, now (Administrator)
        app.MapPost("/api/v1/process/sweep", async (HttpContext http, CancellationToken ct) =>
        {
            await authz.RequireAsync(http.Session(), http.User(), "Grant.Administer", "Grant", null, "POST process.sweep", http.Connection.RemoteIpAddress?.ToString() ?? "", ct);
            var (instances, changes, detail) = await SweepService.SweepAsync(connectionString, catalog, log, ct);
            return Results.Json(new { instances, changes, detail });
        });
    }

    // ------------------------------------------------------------------ helpers
    private sealed record WorkflowHeadRow(Guid EntityId, string Key, string SubjectKind, Guid Subject, Guid? WorkRequest, string CurrentState, JsonObject Document);

    private static async Task<WorkflowHeadRow> WorkflowHead(SqlSession s, Guid id, CancellationToken ct)
    {
        var r = (await s.RowsAsync("""
            SELECT w.EntityId, d.DefinitionKey, w.SubjectKind, w.SubjectEntityId, w.CurrentState, dv.PayloadText,
                   (SELECT TOP (1) pi.WorkRequestEntityId FROM process.vProcedureInstance pi WHERE pi.WorkflowInstanceEntityId = w.EntityId) AS WorkRequestEntityId
            FROM process.vWorkflowInstance w JOIN config.vDefinitionVersion dv ON dv.RowId = w.WorkflowDefinitionVersionRowId JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
            WHERE w.EntityId = @w
            """, new Dictionary<string, object?> { ["@w"] = id }, ct)).FirstOrDefault() as JsonObject ?? throw new ApiException(404, "unknown_instance", "No workflow instance has that id.");
        return new(id, r["DefinitionKey"]!.GetValue<string>(), r["SubjectKind"]!.GetValue<string>(), Guid.Parse(r["SubjectEntityId"]!.GetValue<string>()), G(r["WorkRequestEntityId"]), r["CurrentState"]!.GetValue<string>(), (JsonObject)JsonNode.Parse(r["PayloadText"]!.GetValue<string>())!);
    }

    private static async Task<WorkflowHeadRow?> WorkflowFor(SqlSession s, string key, Guid subject, CancellationToken ct)
    {
        var r = (await s.RowsAsync("""
            SELECT TOP (1) w.EntityId FROM process.vWorkflowInstance w JOIN config.vDefinitionVersion dv ON dv.RowId = w.WorkflowDefinitionVersionRowId JOIN config.vDefinition d ON d.EntityId = dv.DefinitionEntityId
            WHERE d.DefinitionKey = @k AND w.SubjectEntityId = @s AND w.CompletedAt IS NULL ORDER BY w.StartedAt DESC
            """, new Dictionary<string, object?> { ["@k"] = key, ["@s"] = subject }, ct)).FirstOrDefault() as JsonObject;
        return r is null ? null : await WorkflowHead(s, Guid.Parse(r["EntityId"]!.GetValue<string>()), ct);
    }

    /// <summary>The when-guards of a transition, evaluated over the workflow's subject: [{"ok":bool,"unknown":[…]}] index-aligned with requires[] (a procedure guard is the database's, marked here as deferred).</summary>
    private static JsonArray GuardVerdicts(SqlSession s, WorkflowHeadRow wf, string transition, DateTimeOffset now)
    {
        var t = (wf.Document["transitions"] as JsonArray)?.FirstOrDefault(x => x?["from"]?.GetValue<string>() == wf.CurrentState && x?["name"]?.GetValue<string>() == transition) as JsonObject;
        var verdicts = new JsonArray();
        if (t?["requires"] is not JsonArray reqs) return verdicts;
        var reader = new DbFactReader(s.Connection, null);
        foreach (var g in reqs)
        {
            if (g?["when"] is JsonObject when)
            {
                var r = Evaluator.Evaluate(when, reader, new Ref(wf.Subject.ToString(), wf.SubjectKind), now);
                verdicts.Add(new JsonObject { ["ok"] = r.Value is true, ["value"] = r.Value?.ToString(), ["unknown"] = new JsonArray(r.Unknowns.Distinct().Select(x => (JsonNode)JsonValue.Create(x)).ToArray()) });
            }
            else verdicts.Add(new JsonObject { ["procedure"] = g?["procedure"]?.DeepClone(), ["ok"] = null });
        }
        return verdicts;
    }

    private static async Task<List<Guid>> StartedRuns(SqlSession s, Guid workflowInstance, CancellationToken ct)
        => (await s.RowsAsync("SELECT EntityId FROM process.vProcedureInstance WHERE WorkflowInstanceEntityId = @w AND ParentInstanceEntityId IS NULL AND State IN (N'Running', N'Held')", new Dictionary<string, object?> { ["@w"] = workflowInstance }, ct))
            .Select(r => Guid.Parse(r!["EntityId"]!.GetValue<string>())).ToList();

    private static DocBlock? FindDoc(DocBlock b, string path, string kind)
    {
        if (b.Path == path && b.Kind == kind) return b;
        foreach (var c in b.Children) if (FindDoc(c, path, kind) is { } f) return f;
        return null;
    }

    private static Guid? G(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) && Guid.TryParse(s, out var g) ? g : null;

    private static async Task<JsonObject> ReadObject(HttpContext http, CancellationToken ct)
    {
        if (!http.Request.HasJsonContentType()) throw new ApiException(415, "unsupported_media_type", "POST bodies must be application/json.");
        if (http.Request.ContentLength is 0) return new JsonObject();
        try
        {
            var node = await JsonNode.ParseAsync(http.Request.Body, cancellationToken: ct);
            return node switch { null => new JsonObject(), JsonObject o => o, _ => throw new ApiException(400, "bad_json", "The body must be a JSON object.") };
        }
        catch (JsonException) { throw new ApiException(400, "bad_json", "The body is not valid JSON."); }
    }
}
