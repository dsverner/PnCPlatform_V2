using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;

namespace PnC.Api.Engine;

// #171 (2026-09-16), #214 (2026-09-20). The compliance worker: two clocks, one evaluator.
//   The queue   every Engine:ComplianceQueueSeconds (default 5): the pending evaluation requests (compliance.EvaluationRequest,
//               left by the API after a write that changed a fact the rules read — Engine/ComplianceTriggers.cs) are taken
//               together, expanded to the devices affected (compliance.ExpandEvaluationRequests), evaluated in one Effective pass
//               (trigger FactChanged; RuleApproved when a rule, formula or derivation was approved, which means every
//               candidate) and marked served with the run. The owner: "Should the evaluation be an automatic function of what
//               is presently known about the system?" — this is that function.
//   The hour    every Engine:ComplianceMinutes (default 60; <= 0 disables): every effective rule over every candidate
//               (trigger Scheduled) — the catch-all for anything time-based, for writes made in SQL directly, and for the
//               fact catalogue's own changes (a ruling in ref.AnsiFunction), which leave no request.
// Like the sweep, both connections carry no person: personnel.ResolveActor attributes the writes to the platform's System
// actor; the request row keeps who made the change that asked for the pass. Effective passes never overlap
// (ComplianceEvaluator.Gate).
public sealed class ComplianceService(IConfiguration config, Catalog catalog, ILogger<ComplianceService> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var minutes = config.GetValue<int?>("Engine:ComplianceMinutes") ?? 60;
        var seconds = config.GetValue<int?>("Engine:ComplianceQueueSeconds") ?? 5;
        var tasks = new List<Task>();
        if (minutes <= 0) log.LogInformation("Compliance pass disabled (Engine:ComplianceMinutes = {Minutes})", minutes);
        else { log.LogInformation("Compliance pass every {Minutes} min", minutes); tasks.Add(HourlyAsync(TimeSpan.FromMinutes(minutes), stoppingToken)); }
        if (seconds <= 0) log.LogInformation("Compliance queue disabled (Engine:ComplianceQueueSeconds = {Seconds})", seconds);
        else { log.LogInformation("Compliance queue every {Seconds} s", seconds); tasks.Add(QueueAsync(TimeSpan.FromSeconds(seconds), stoppingToken)); }
        try { await Task.WhenAll(tasks); } catch (OperationCanceledException) { }
    }

    async Task HourlyAsync(TimeSpan every, CancellationToken ct)
    {
        // the catch-up: a candidate device with no standing evaluation at all (the first start after #214, a device that became a
        // candidate through a write made in SQL) is not left blank for an hour — one full pass runs at once, then the clock
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(10), ct);
            await using var s0 = await SqlSession.OpenAsync(config["Database:ConnectionString"]!, null, ct);
            var blank = await s0.ScalarAsync<int?>("SELECT TOP (1) 1 FROM compliance.vRuleCandidateDevice c WHERE NOT EXISTS (SELECT 1 FROM compliance.SubjectEvaluation e WHERE e.SubjectKind = N'Device' AND e.SubjectEntityId = c.DeviceEntityId)",
                new Dictionary<string, object?>(), ct);
            if (blank is not null)
            {
                var r0 = await new ComplianceEvaluator(s0, catalog, log).EvaluateAsync(null, null, null, "Effective", "Scheduled", "catch-up: a candidate device had no standing evaluation", ct);
                log.LogInformation("Compliance catch-up pass: {Subjects} subject(s), {Opened} opened, {Closed} closed", r0.Subjects, r0.Opened, r0.Closed);
            }
        }
        catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Compliance catch-up pass failed"); }
        using var timer = new PeriodicTimer(every);
        while (await timer.WaitForNextTickAsync(ct))
        {
            try
            {
                await using var s = await SqlSession.OpenAsync(config["Database:ConnectionString"]!, null, ct);
                var r = await new ComplianceEvaluator(s, catalog, log).EvaluateAsync(null, null, "Effective", "Scheduled", ct);
                log.LogInformation("Compliance pass: {Rules} rule(s), {Subjects} subject(s), {Opened} opened, {Closed} closed, {Unknown} unknown, {Errors} error(s)",
                    r.Rules, r.Subjects, r.Opened, r.Closed, r.Unknown, r.Errors);
            }
            catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Compliance pass failed"); }
        }
    }

    async Task QueueAsync(TimeSpan every, CancellationToken ct)
    {
        using var timer = new PeriodicTimer(every);
        while (await timer.WaitForNextTickAsync(ct))
        {
            try
            {
                await using var s = await SqlSession.OpenAsync(config["Database:ConnectionString"]!, null, ct);
                var served = await ServePendingAsync(s, catalog, log, ct);
                if (served is not null)
                    log.LogInformation("Compliance queue: {Requests} request(s) → {Devices} device(s), {Opened} opened, {Closed} closed ({Trigger})",
                        served.Value.requests, served.Value.devices, served.Value.report?.Opened, served.Value.report?.Closed, served.Value.trigger);
            }
            catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Compliance queue failed"); }
        }
    }

    /// <summary>One turn of the queue: take what is pending, evaluate the devices it touches, mark it served. Null when
    /// nothing was pending. Also what the smoke's wait observes (the requests turn IsPending = 0).</summary>
    public static async Task<(int requests, int devices, string trigger, EvaluationReport? report)?> ServePendingAsync(SqlSession s, Catalog catalog, ILogger log, CancellationToken ct)
    {
        var pending = (await s.RowsAsync("SELECT RequestId, SubjectKind, SubjectEntityId, Reason FROM compliance.EvaluationRequest WHERE ProcessedAt IS NULL ORDER BY RequestedAt",
            new Dictionary<string, object?>(), ct)).Select(r => (JsonObject)r!).ToList();
        if (pending.Count == 0) return null;
        var ids = pending.Select(r => r["RequestId"]!.GetValue<string>()).ToList();
        var idsJson = JsonSerializer.Serialize(ids);
        var all = pending.Any(r => r["SubjectKind"]!.GetValue<string>() == "All");
        var trigger = all && pending.All(r => (r["Reason"]?.GetValue<string>() ?? "").StartsWith("config.", StringComparison.Ordinal)) ? "RuleApproved" : "FactChanged";
        var reasons = pending.GroupBy(r => r["Reason"]?.GetValue<string>() ?? "").Select(g => $"{g.Key} ×{g.Count()}");
        var notes = $"served {pending.Count} request(s): {string.Join(", ", reasons)}";
        EvaluationReport? report = null;
        int devices;
        if (all)
        {
            report = await new ComplianceEvaluator(s, catalog, log).EvaluateAsync(null, null, null, "Effective", trigger, notes, ct);
            devices = report.Subjects;
        }
        else
        {
            // the candidates and their protects walk are materialised once (compliance.ExpandEvaluationRequests); the inline
            // function this began as re-ran them per request and per branch and timed out under the smoke's load
            var rows = await s.RowsAsync("EXEC compliance.ExpandEvaluationRequests @RequestIds = @ids", new Dictionary<string, object?> { ["@ids"] = idsJson }, ct);
            var list = rows.Select(r => Guid.Parse(((JsonObject)r!)["DeviceEntityId"]!.GetValue<string>())).ToList();
            devices = list.Count;
            if (devices > 0) report = await new ComplianceEvaluator(s, catalog, log).EvaluateAsync(null, null, list, "Effective", trigger, notes, ct);
        }
        var complete = catalog.Procedure("compliance", "EvaluationRequest_Complete") ?? throw new InvalidOperationException("compliance.EvaluationRequest_Complete is not in the catalogue.");
        await s.ExecuteProcedureAsync(complete, new JsonObject { ["RequestIds"] = idsJson, ["RunId"] = report?.RunId.ToString(), ["DevicesFound"] = devices }, ct);
        return (pending.Count, devices, trigger, report);
    }
}
