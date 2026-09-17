using System.Globalization;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Definitions;
using PnC.Api.Endpoints;
using PnC.Formula;

namespace PnC.Api.Engine;

// #171 (2026-09-16): the obligation-rule evaluator. Every rule is a Program.ObligationRule definition (its scope an expression
// over the subject's facts, its requirement a compliance.Requirement); every derived number is a Program.Formula definition
// (asset.formula.<key>). Nothing here knows a standard: the code reads the definitions, evaluates them with PnC.Formula over
// compliance.fFactRead, and opens or closes compliance.ObligationInstance rows. The facts read are the evidence trail
// (ObligationInstanceFact), taken from the reads themselves rather than from the checker's static list, so a parameterised
// fact (device.protects.rating[kind=FourHour]) is recorded with its parameters and its value as read.
//   Preview  — evaluate and report, write nothing (what the compliance panel's "Evaluate now" shows first).
//   Effective — open an instance when the scope is true and none is open for (subject, rule version, requirement, period);
//               close one (NotApplicable) when the scope is false; leave it when Unknown, and say so.
// Subjects: one given, else the candidates (compliance.vRuleCandidateDevice for Device — devices that carry a classification
// or protect a classified asset; compliance.fRuleSubjects for other kinds). Rules sharing one canonical scope are evaluated
// once per subject.

public sealed record FactRead(string Name, string? Params, string Value);

public sealed record Verdict(string RuleKey, string RuleName, Guid RuleVersionRowId, Guid? RequirementEntityId, string SubjectKind, Guid SubjectEntityId,
    string SubjectName, string Result, string? Error, IReadOnlyList<string> Unknowns, IReadOnlyList<FactRead> Reads, Guid? InstanceRowId, string Action,
    string? EvidenceNote, string? RequirementNumber, string? StandardCode, string? StandardVersion);

public sealed record EvaluationReport(DateTimeOffset At, string Mode, int Rules, int Subjects, int Opened, int Closed, int Unchanged, int Unknown, int Errors,
    IReadOnlyList<Verdict> Verdicts, IReadOnlyList<string> RuleErrors, Guid RunId, IReadOnlyList<Derived> Derivations);

/// <summary>What a Program.ClassificationDerivation decided for one subject: the value, why, and what the database did with it.</summary>
public sealed record Derived(string Key, string Kind, string SubjectKind, Guid SubjectEntityId, string SubjectName, string? Value, string Reason,
    IReadOnlyList<FactRead> Reads, string Outcome, string? Error);

public sealed class ComplianceEvaluator(SqlSession s, Catalog catalog, ILogger log)
{
    sealed record Rule(Guid DefinitionEntityId, string Key, string Name, Guid VersionRowId, Guid? RequirementEntityId, string[] SubjectKinds,
        JsonObject Scope, string ScopeKey, string Cadence, string? EvidenceNote, string[] Record, string? RequirementNumber, string? StandardCode, string? StandardVersion);

    sealed record Formula(string Key, JsonObject Expression, string? Type, string? Unit, int? Precision);

    sealed record Derivation(string Key, string Name, Guid VersionRowId, string Kind, string[] SubjectKinds,
        IReadOnlyList<(JsonObject When, string WhenText, string Value)> Cases, string? Else);

    /// <summary>Evaluate every effective rule for the given subject (or the candidates). Mode Preview writes nothing.</summary>
    public async Task<EvaluationReport> EvaluateAsync(string? subjectKind, Guid? subjectEntityId, string mode, string trigger, CancellationToken ct)
    {
        if (mode is not ("Preview" or "Effective")) throw new ApiException(400, "bad_mode", "Mode must be Preview or Effective.");
        var now = await s.NowAsync(ct);
        var cat = await LiveCatalogue.LoadAsync(s, ct);
        var runId = Guid.NewGuid();
        var ruleErrors = new List<string>();
        var rules = await LoadRulesAsync(cat, ruleErrors, ct);
        var formulas = await LoadFormulasAsync(ct);
        var derivations = await LoadDerivationsAsync(cat, ruleErrors, ct);
        var verdicts = new List<Verdict>();
        var derived = new List<Derived>();
        int opened = 0, closed = 0, unchanged = 0, unknown = 0, errors = 0;

        // subjects per kind
        var subjects = new Dictionary<string, List<(Guid Id, string Name)>>(StringComparer.Ordinal);
        foreach (var kind in rules.SelectMany(r => r.SubjectKinds).Distinct(StringComparer.Ordinal))
        {
            if (subjectEntityId is Guid one)
            {
                if (subjectKind is not null && !string.Equals(subjectKind, kind, StringComparison.Ordinal)) continue;
                var name = await s.ScalarAsync<string>("SELECT TOP (1) Name FROM asset.vAsset WHERE EntityId = @id", new Dictionary<string, object?> { ["@id"] = one }, ct)
                           ?? await s.ScalarAsync<string>("SELECT TOP (1) Name FROM location.vNode WHERE EntityId = @id", new Dictionary<string, object?> { ["@id"] = one }, ct)
                           ?? one.ToString();
                subjects[kind] = [(one, name)];
                continue;
            }
            var sql = kind == "Device"
                ? "SELECT DeviceEntityId AS EntityId, Name FROM compliance.vRuleCandidateDevice"
                : "SELECT EntityId, Name FROM compliance.fRuleSubjects(@kinds)";
            var rows = await s.RowsAsync(sql, new Dictionary<string, object?> { ["@kinds"] = "[\"" + kind + "\"]" }, ct);
            subjects[kind] = rows.Select(r => (Guid.Parse(r!["EntityId"]!.GetValue<string>()), r!["Name"]?.GetValue<string>() ?? "")).ToList();
        }

        var perRule = rules.ToDictionary(r => r.VersionRowId, _ => (scoped: 0, opened: 0, closed: 0, unchanged: 0));
        // the run row first: an instance references its run (FK), so the row exists before the first write; completed with the counts at the end
        await s.ExecuteProcedureAsync(Proc("StartEvaluationRun"), new JsonObject
        {
            ["RuleDefinitionVersionRowId"] = rules.Count == 1 ? rules[0].VersionRowId.ToString() : null, ["Mode"] = mode, ["Trigger"] = trigger,
            ["StartedAt"] = now.ToString("o"), ["RunId"] = runId.ToString(),
        }, ct);
        foreach (var (kind, list) in subjects)
        {
            var kindRules = rules.Where(r => r.SubjectKinds.Contains(kind, StringComparer.Ordinal)).ToList();
            var kindDerivations = derivations.Where(d => d.SubjectKinds.Contains(kind, StringComparer.Ordinal)).ToList();
            if (kindRules.Count == 0 && kindDerivations.Count == 0) continue;
            foreach (var (id, name) in list)
            {
                var subject = new Ref(id.ToString(), kind);
                var reader = new TracingFormulaReader(new DbFactReader(s.Connection, null), formulas);
                // the derivations first: a rule's scope reads the classification they write, in this same pass
                foreach (var d in kindDerivations)
                    derived.Add(await DeriveAsync(d, subject, kind, id, name, reader, mode, now, ct));
                foreach (var group in kindRules.GroupBy(r => r.ScopeKey, StringComparer.Ordinal))
                {
                    reader.Reads.Clear();
                    object value; IReadOnlyList<string> unknowns; string? error = null;
                    try
                    {
                        var r = Evaluator.Evaluate(group.First().Scope, reader, subject, now);
                        value = r.Value; unknowns = r.Unknowns.Distinct().ToList();
                    }
                    catch (FormulaException e) { value = Unknown.Value; unknowns = []; error = e.Message; }
                    catch (Exception e) when (e is not OperationCanceledException) { value = Unknown.Value; unknowns = []; error = e.Message; }
                    var result = error is not null ? "error" : value is true ? "true" : value is false ? "false" : "unknown";
                    var scopeReads = reader.Reads.ToList();
                    foreach (var rule in group)
                    {
                        var reads = new List<FactRead>(scopeReads);
                        if (result == "true" && rule.Record.Length > 0)
                        {
                            reader.Reads.Clear();
                            foreach (var f in rule.Record) reader.ReadNamed(subject, f, now);
                            reads.AddRange(reader.Reads);
                        }
                        // one line per fact: a formula read inside another formula is replayed wherever it was used, and the
                        // trail is a list of what was read, not of how many times (the last value read is the one recorded)
                        reads = reads.GroupBy(x => (x.Name, x.Params)).Select(g => g.Last()).ToList();
                        var c = perRule[rule.VersionRowId]; c.scoped++;
                        Guid? instanceRowId = null; string action = "none";
                        try
                        {
                            var open = await OpenInstanceAsync(rule, id, now, ct);
                            instanceRowId = open?.RowId;
                            if (result == "true")
                            {
                                if (open is null)
                                {
                                    action = "open";
                                    if (mode == "Effective") { instanceRowId = await OpenAsync(rule, kind, id, now, runId, reads, ct); }
                                    c.opened++; opened++;
                                }
                                else { action = "unchanged"; c.unchanged++; unchanged++; }
                            }
                            else if (result == "false")
                            {
                                if (open is not null)
                                {
                                    action = "close";
                                    if (mode == "Effective") await CloseAsync(rule, open, kind, id, runId, ct);
                                    c.closed++; closed++;
                                }
                                else { action = "none"; c.unchanged++; unchanged++; }
                            }
                            else { action = "unchanged"; c.unchanged++; if (result == "error") errors++; else unknown++; }
                        }
                        catch (Exception e) when (e is not OperationCanceledException)
                        {
                            log.LogError(e, "Compliance: rule {Rule} subject {Subject}", rule.Key, id);
                            error = (error is null ? "" : error + "; ") + e.Message; result = "error"; errors++;
                        }
                        perRule[rule.VersionRowId] = c;
                        verdicts.Add(new Verdict(rule.Key, rule.Name, rule.VersionRowId, rule.RequirementEntityId, kind, id, name, result, error, unknowns, reads,
                            instanceRowId, action, rule.EvidenceNote, rule.RequirementNumber, rule.StandardCode, rule.StandardVersion));
                    }
                }
            }
        }

        var completed = await s.NowAsync(ct);
        await s.ExecuteProcedureAsync(Proc("RuleEvaluationRun_Complete"), new JsonObject
        {
            ["RunId"] = runId.ToString(), ["CompletedAt"] = completed.ToString("o"), ["SubjectsScoped"] = perRule.Values.Sum(c => c.scoped),
            ["InstancesOpened"] = opened, ["InstancesClosed"] = closed, ["InstancesUnchanged"] = unchanged,
        }, ct);
        return new EvaluationReport(now, mode, rules.Count, subjects.Values.Sum(l => l.Count), opened, closed, unchanged, unknown, errors, verdicts, ruleErrors, runId, derived);
    }

    ProcInfo Proc(string name) => catalog.Procedure("compliance", name) ?? throw new ApiException(500, "internal", $"compliance.{name} is not in the catalogue.");
    ProcInfo Proc2(string schema, string name) => catalog.Procedure(schema, name) ?? throw new ApiException(500, "internal", $"{schema}.{name} is not in the catalogue.");

    sealed record OpenRow(Guid RowId, Guid EntityId, DateTimeOffset PeriodStartAt, DateTimeOffset? PeriodEndAt);

    async Task<OpenRow?> OpenInstanceAsync(Rule rule, Guid subject, DateTimeOffset now, CancellationToken ct)
    {
        var (start, _) = Period(rule.Cadence, now);
        var rows = await s.RowsAsync("""
            SELECT TOP (1) RowId, EntityId, PeriodStartAt, PeriodEndAt FROM compliance.vObligationInstance
            WHERE SubjectEntityId = @s AND RuleDefinitionVersionRowId = @v AND Status = N'Open'
              AND (@req IS NULL OR RequirementEntityId = @req) AND (PeriodEndAt IS NULL OR PeriodEndAt >= @start)
            ORDER BY PeriodStartAt DESC
            """, new Dictionary<string, object?> { ["@s"] = subject, ["@v"] = rule.VersionRowId, ["@req"] = rule.RequirementEntityId, ["@start"] = start }, ct);
        var r = rows.FirstOrDefault() as JsonObject;
        if (r is null) return null;
        return new OpenRow(Guid.Parse(r["RowId"]!.GetValue<string>()), Guid.Parse(r["EntityId"]!.GetValue<string>()),
            DateTimeOffset.Parse(r["PeriodStartAt"]!.GetValue<string>(), CultureInfo.InvariantCulture),
            r["PeriodEndAt"] is null ? null : DateTimeOffset.Parse(r["PeriodEndAt"]!.GetValue<string>(), CultureInfo.InvariantCulture));
    }

    /// <summary>The obligation period the cadence text names: "once" → from the run instant, open-ended; "every calendar_year" → the run's calendar year.</summary>
    static (DateTimeOffset start, DateTimeOffset? end) Period(string cadence, DateTimeOffset now)
    {
        var c = cadence.Trim().ToLowerInvariant();
        if (c.StartsWith("every calendar_year", StringComparison.Ordinal))
        {
            var start = new DateTimeOffset(now.Year, 1, 1, 0, 0, 0, now.Offset);
            return (start, start.AddYears(1).AddTicks(-1));
        }
        if (c.StartsWith("every calendar_quarter", StringComparison.Ordinal))
        {
            var q = (now.Month - 1) / 3;
            var start = new DateTimeOffset(now.Year, q * 3 + 1, 1, 0, 0, 0, now.Offset);
            return (start, start.AddMonths(3).AddTicks(-1));
        }
        if (c.StartsWith("every calendar_month", StringComparison.Ordinal))
        {
            var start = new DateTimeOffset(now.Year, now.Month, 1, 0, 0, 0, now.Offset);
            return (start, start.AddMonths(1).AddTicks(-1));
        }
        return (now, null);   // once, and any cadence this version does not compute a period for (recorded as open-ended)
    }

    async Task<Guid> OpenAsync(Rule rule, string kind, Guid subject, DateTimeOffset now, Guid runId, IReadOnlyList<FactRead> reads, CancellationToken ct)
    {
        var (start, end) = Period(rule.Cadence, now);
        var res = await s.ExecuteProcedureAsync(Proc("ObligationInstance_Add"), new JsonObject
        {
            ["SubjectKind"] = kind, ["SubjectEntityId"] = subject.ToString(), ["RuleDefinitionVersionRowId"] = rule.VersionRowId.ToString(),
            ["RequirementEntityId"] = rule.RequirementEntityId?.ToString(), ["PeriodStartAt"] = start.ToString("o"), ["PeriodEndAt"] = end?.ToString("o"),
            ["Status"] = "Open", ["EvaluationRunId"] = runId.ToString(),
        }, ct);
        var rowId = Guid.Parse(res["RowId"]!.GetValue<string>());
        foreach (var f in reads)
            await s.ExecuteProcedureAsync(Proc("ObligationInstanceFact_Append"), new JsonObject
            {
                ["ObligationInstanceRowId"] = rowId.ToString(), ["FactName"] = f.Params is null ? f.Name : f.Name + f.Params,
                ["ValueAsRead"] = f.Value.Length > 400 ? f.Value[..400] : f.Value,
            }, ct);
        return rowId;
    }

    async Task CloseAsync(Rule rule, OpenRow open, string kind, Guid subject, Guid runId, CancellationToken ct)
    {
        await s.ExecuteProcedureAsync(Proc("ObligationInstance_Revise"), new JsonObject
        {
            ["EntityId"] = open.EntityId.ToString(), ["SubjectKind"] = kind, ["SubjectEntityId"] = subject.ToString(),
            ["RuleDefinitionVersionRowId"] = rule.VersionRowId.ToString(), ["RequirementEntityId"] = rule.RequirementEntityId?.ToString(),
            ["PeriodStartAt"] = open.PeriodStartAt.ToString("o"), ["PeriodEndAt"] = open.PeriodEndAt?.ToString("o"),
            ["Status"] = "NotApplicable", ["EvaluationRunId"] = runId.ToString(),
        }, ct);
    }

    async Task<List<Rule>> LoadRulesAsync(Catalogue cat, List<string> errors, CancellationToken ct)
    {
        var rows = await s.RowsAsync("""
            SELECT r.DefinitionEntityId, r.DefinitionKey, r.Name, r.EffectiveVersionRowId, r.RequirementEntityId, dv.PayloadText,
                   q.RequirementNumber, sv.StandardCode, sv.VersionLabel
            FROM compliance.vObligationRule r
            JOIN config.vDefinitionVersion dv ON dv.RowId = r.EffectiveVersionRowId
            LEFT JOIN compliance.vRequirement q ON q.EntityId = r.RequirementEntityId
            LEFT JOIN compliance.vStandardVersion sv ON sv.RowId = q.StandardVersionRowId
            WHERE r.IsEffective = 1
            """, new Dictionary<string, object?>(), ct);
        var list = new List<Rule>();
        foreach (var r in rows.Select(x => (JsonObject)x!))
        {
            var key = r["DefinitionKey"]!.GetValue<string>();
            try
            {
                var payload = (JsonObject)JsonNode.Parse(r["PayloadText"]!.GetValue<string>())!;
                var scope = payload["scope"] as JsonObject;
                if (scope is null && payload["scopeText"]?.GetValue<string>() is { } st) scope = Parser.Parse(st);
                if (scope is null) { errors.Add($"{key}: no scope"); continue; }
                var kinds = (payload["subjectKinds"] as JsonArray)?.Select(k => k!.GetValue<string>()).ToArray() ?? ["Device"];
                new Checker(cat).Check(scope, new Dictionary<string, FormulaType>(), kinds.FirstOrDefault());
                var cadence = payload["cadenceText"]?.GetValue<string>() ?? "once";
                var record = (payload["record"] as JsonArray)?.Select(k => k!.GetValue<string>()).ToArray() ?? [];
                list.Add(new Rule(Guid.Parse(r["DefinitionEntityId"]!.GetValue<string>()), key, r["Name"]!.GetValue<string>(),
                    Guid.Parse(r["EffectiveVersionRowId"]!.GetValue<string>()),
                    r["RequirementEntityId"] is null ? (Guid?)null : Guid.Parse(r["RequirementEntityId"]!.GetValue<string>()), kinds, scope,
                    Canonical.ToCanonical(scope), cadence, payload["evidenceNote"]?.GetValue<string>(), record,
                    r["RequirementNumber"]?.GetValue<string>(), r["StandardCode"]?.GetValue<string>(), r["VersionLabel"]?.GetValue<string>()));
            }
            catch (Exception e) when (e is not OperationCanceledException) { errors.Add($"{key}: {e.Message}"); }
        }
        return list;
    }

    /// <summary>The effective Program.ClassificationDerivation documents. A case's expression is checked against the catalogue
    /// the way a rule's scope is, so a derivation that names a fact the platform does not have is reported, not run.</summary>
    async Task<List<Derivation>> LoadDerivationsAsync(Catalogue cat, List<string> errors, CancellationToken ct)
    {
        var rows = await s.RowsAsync("""
            SELECT d.DefinitionKey, d.Name, dv.RowId, dv.PayloadText FROM config.vDefinition d
            JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId AND dv.Status = N'Effective'
            WHERE d.DefinitionKind = N'Program.ClassificationDerivation'
            """, new Dictionary<string, object?>(), ct);
        var list = new List<Derivation>();
        foreach (var r in rows.Select(x => (JsonObject)x!))
        {
            var key = r["DefinitionKey"]!.GetValue<string>();
            try
            {
                var payload = (JsonObject)JsonNode.Parse(r["PayloadText"]!.GetValue<string>())!;
                var kind = payload["kind"]?.GetValue<string>() ?? throw new FormulaException("bad_document", "the derivation names no classification kind");
                var kinds = (payload["subjectKinds"] as JsonArray)?.Select(k => k!.GetValue<string>()).ToArray() ?? ["Device"];
                var cases = new List<(JsonObject, string, string)>();
                foreach (var c in (payload["cases"] as JsonArray) ?? [])
                {
                    var co = (JsonObject)c!;
                    var when = co["when"] as JsonObject ?? Parser.Parse(co["whenText"]!.GetValue<string>());
                    new Checker(cat).Check(when, new Dictionary<string, FormulaType>(), kinds.FirstOrDefault());
                    cases.Add((when, co["whenText"]?.GetValue<string>() ?? Printer.Print(when), co["value"]!.GetValue<string>()));
                }
                list.Add(new Derivation(key, r["Name"]!.GetValue<string>(), Guid.Parse(r["RowId"]!.GetValue<string>()), kind, kinds, cases,
                    payload["else"]?.GetValue<string>()));
            }
            catch (Exception e) when (e is not OperationCanceledException) { errors.Add($"{key}: {e.Message}"); }
        }
        return list;
    }

    /// <summary>Evaluate one derivation for one subject and, in Effective mode, write what it decided.
    /// FORMULA-GRAMMAR grammar-1: the first case that is true gives the value; when none is true and any is Unknown the answer is
    /// Unknown (not the else), so a device whose protected element carries no BES status is left undetermined rather than declared
    /// Not BCA. A value a person recorded is never overwritten (asset.DeriveClassification returns RecordedStands).</summary>
    async Task<Derived> DeriveAsync(Derivation d, Ref subject, string kind, Guid id, string name, TracingFormulaReader reader,
                                    string mode, DateTimeOffset now, CancellationToken ct)
    {
        reader.Reads.Clear();
        string? value = null, error = null, reason;
        var sawUnknown = false;
        try
        {
            foreach (var (when, whenText, v) in d.Cases)
            {
                var r = Evaluator.Evaluate(when, reader, subject, now);
                if (r.Value is true) { value = v; reason = whenText; goto decided; }
                if (r.Value is not false) sawUnknown = true;
            }
            value = sawUnknown ? null : d.Else;
            reason = sawUnknown ? "undetermined: " + string.Join(", ", reader.Reads.Where(x => x.Value == "unknown").Select(x => x.Name).Distinct())
                                : "no case matched";
            goto decided;
        }
        catch (Exception e) when (e is not OperationCanceledException) { error = e.Message; reason = "the derivation could not be evaluated"; }
    decided:
        var reads = reader.Reads.GroupBy(x => (x.Name, x.Params)).Select(g => g.Last()).ToList();
        var outcome = "Preview";
        if (error is null && mode == "Effective")
        {
            var res = await s.ExecuteProcedureAsync(Proc2("asset", "DeriveClassification"), new JsonObject
            {
                ["SubjectKind"] = "Asset",                 // a device is an Asset subject (asset.Classification's CHECK)
                ["SubjectEntityId"] = id.ToString(), ["ClassificationKindCode"] = d.Kind, ["ClassificationValue"] = value,
                ["DerivationDefinitionVersionRowId"] = d.VersionRowId.ToString(), ["DeterminedAt"] = now.ToString("o"),
            }, ct);
            outcome = res["Outcome"]?.GetValue<string>() ?? "Set";
        }
        return new Derived(d.Key, d.Kind, kind, id, name, value, reason!, reads, outcome, error);
    }

    async Task<Dictionary<string, Formula>> LoadFormulasAsync(CancellationToken ct)
    {
        var rows = await s.RowsAsync("""
            SELECT d.DefinitionKey, dv.PayloadText FROM config.vDefinition d
            JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId AND dv.Status = N'Effective'
            WHERE d.DefinitionKind = N'Program.Formula'
            """, new Dictionary<string, object?>(), ct);
        var map = new Dictionary<string, Formula>(StringComparer.Ordinal);
        foreach (var r in rows.Select(x => (JsonObject)x!))
        {
            var key = r["DefinitionKey"]!.GetValue<string>();
            try
            {
                var payload = (JsonObject)JsonNode.Parse(r["PayloadText"]!.GetValue<string>())!;
                var expr = payload["expression"] as JsonObject;
                if (expr is null && payload["expressionText"]?.GetValue<string>() is { } et) expr = Parser.Parse(et);
                if (expr is null) continue;
                var pub = payload["publishes"] as JsonObject;
                map[key] = new Formula(key, expr, pub?["type"]?.GetValue<string>(), pub?["unit"]?.GetValue<string>(), pub?["precision"]?.GetValue<int>());
            }
            catch (Exception e) when (e is not OperationCanceledException) { log.LogWarning("Compliance: formula {Key} unreadable: {Error}", key, e.Message); }
        }
        return map;
    }

    /// <summary>Resolves asset.formula.&lt;key&gt; by evaluating the effective formula; traces every read (the evidence trail).</summary>
    sealed class TracingFormulaReader(IFactReader inner, IReadOnlyDictionary<string, Formula> formulas) : IFactReader
    {
        public List<FactRead> Reads { get; } = new();
        // a formula's value and the reads it made: a second read of the same formula is served from here, and its reads are
        // replayed into the trace, so the evidence trail of an obligation shows what the number was computed from even when the
        // value itself was already known (the rule's scope reads a formula, then its record list reads it again — #171)
        readonly Dictionary<string, (object Value, List<FactRead> Reads)> _cache = new(StringComparer.Ordinal);
        readonly HashSet<string> _evaluating = new(StringComparer.Ordinal);

        public object? Read(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at)
        {
            object? value;
            if (name.StartsWith("asset.formula.", StringComparison.Ordinal))
            {
                var key = name["asset.formula.".Length..];
                var cacheKey = (subject is Ref r ? r.Id : subject?.ToString()) + "|" + key;
                if (_cache.TryGetValue(cacheKey, out var hit))
                {
                    value = hit.Value;
                    Reads.AddRange(hit.Reads);
                }
                else
                {
                    var from = Reads.Count;
                    value = Unknown.Value;
                    if (formulas.TryGetValue(key, out var f) && _evaluating.Add(cacheKey))
                    {
                        try { value = Publish(Evaluator.Evaluate(f.Expression, this, subject, at).Value, f); }
                        catch (FormulaException) { value = Unknown.Value; }
                        finally { _evaluating.Remove(cacheKey); }
                    }
                    _cache[cacheKey] = (value!, Reads.Skip(from).ToList());
                }
            }
            else value = inner.Read(subject, name, parameters, at);
            Reads.Add(new FactRead(name, parameters.Count == 0 ? null : "[" + string.Join(",", parameters.Select(kv => kv.Key + "=" + Text(kv.Value))) + "]", Text(value)));
            return value;
        }

        public void ReadNamed(object? subject, string name, DateTimeOffset at) => Read(subject, name, new Dictionary<string, object>(), at);

        static object Publish(object value, Formula f)
        {
            if (value is Quantity q && f.Type == "num")
            {
                if (f.Unit is not null && q.Unit is not null && q.Unit != f.Unit && Units.Convert(q.Value, q.Unit, f.Unit) is decimal cv) q = q with { Value = cv, Unit = f.Unit };
                else if (f.Unit is not null && q.Unit is null) q = q with { Unit = f.Unit };
                if (f.Precision is int p) q = q with { Value = Math.Round(q.Value, p, MidpointRounding.AwayFromZero) };
                return q;
            }
            return value;
        }

        public static string Text(object? v) => v switch
        {
            null => "unknown",
            Unknown => "unknown",
            Quantity q => Values.DecText(q.Value) + (q.Unit is null ? "" : " " + q.Unit) + (q.Base is null ? "" : "@" + q.Base),
            Ref r => r.Kind + ":" + r.Id,
            List<object> l => "{" + string.Join(", ", l.Select(Text)) + "}",
            DateTimeOffset d => d.ToString("o"),
            bool b => b ? "true" : "false",
            _ => v.ToString() ?? "",
        };
    }
}
