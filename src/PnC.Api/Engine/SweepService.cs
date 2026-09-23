using PnC.Api.Data;

namespace PnC.Api.Engine;

// PROCEDURE-ENGINE §4.1 (#54; W4, decision #111). The scheduled sweep: every Engine:SweepMinutes (default 15 — the
// design's "platform setting" has no store yet, so it is the host's configuration) every Running or Held procedure
// instance is re-evaluated at the sweep instant, which is what releases a time-based hold with nobody signed in and
// expires a hold past its maxDuration. The sweep's connection carries no person: personnel.ResolveActor attributes its
// writes to the platform's own System actor (the SQL login's), which is what a scheduled act is.
public sealed class SweepService(IConfiguration config, Catalog catalog, ILogger<SweepService> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var minutes = config.GetValue<int?>("Engine:SweepMinutes") ?? 15;
        if (minutes <= 0) { log.LogInformation("Engine sweep disabled (Engine:SweepMinutes = {Minutes})", minutes); return; }
        log.LogInformation("Engine sweep every {Minutes} min", minutes);
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(minutes));
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                try { var r = await SweepAsync(config["Database:ConnectionString"]!, catalog, log, stoppingToken); log.LogInformation("Engine sweep: {Instances} instance(s), {Changes} change(s)", r.instances, r.changes); }
                catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Engine sweep failed"); }
            }
        }
        catch (OperationCanceledException) { }
    }

    /// <summary>One sweep over every live instance; also the DEV endpoint's body (POST /api/v1/process/sweep).</summary>
    public static async Task<(int instances, int changes, List<object> detail)> SweepAsync(string connectionString, Catalog catalog, ILogger log, CancellationToken ct)
    {
        await using var s = await SqlSession.OpenAsync(connectionString, null, ct);
        var now = await s.NowAsync(ct);
        // #228: a run whose governing workflow has ended (a cancelled request) is never advanced
        var ids = (await s.RowsAsync("SELECT p.EntityId FROM process.vProcedureInstance p LEFT JOIN process.WorkflowInstance w ON w.EntityId = p.WorkflowInstanceEntityId AND w.IsDeleted = 0 WHERE p.State IN (N'Running', N'Held') AND p.ParentInstanceEntityId IS NULL AND w.CompletedAt IS NULL ORDER BY p.StartedAt", new Dictionary<string, object?>(), ct))
            .Select(r => Guid.Parse(r!["EntityId"]!.GetValue<string>())).ToList();
        // children first would double the work: a child's completion advances its parent through the parent's next pass
        var children = (await s.RowsAsync("SELECT p.EntityId FROM process.vProcedureInstance p LEFT JOIN process.WorkflowInstance w ON w.EntityId = p.WorkflowInstanceEntityId AND w.IsDeleted = 0 WHERE p.State IN (N'Running', N'Held') AND p.ParentInstanceEntityId IS NOT NULL AND w.CompletedAt IS NULL ORDER BY p.StartedAt", new Dictionary<string, object?>(), ct))
            .Select(r => Guid.Parse(r!["EntityId"]!.GetValue<string>())).ToList();
        var interp = new Interpreter(s, catalog, log);
        int changes = 0; var detail = new List<object>();
        foreach (var id in children.Concat(ids))
        {
            try
            {
                var r = await interp.AdvanceAsync(id, now, ct);
                changes += r.Changes;
                if (r.Changes > 0 || r.Notes.Count > 0) detail.Add(new { instance = id, r.Changes, r.Completed, r.Notes });
            }
            catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Engine sweep: instance {Instance}", id); detail.Add(new { instance = id, error = e.Message }); }
        }
        return (ids.Count + children.Count, changes, detail);
    }
}
