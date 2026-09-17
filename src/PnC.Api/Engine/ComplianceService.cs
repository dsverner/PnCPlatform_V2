using PnC.Api.Data;

namespace PnC.Api.Engine;

// #171 (2026-09-16). The scheduled compliance pass: every Engine:ComplianceMinutes (default 60; <= 0 disables) every
// effective obligation rule is evaluated over its candidate subjects (ComplianceEvaluator, mode Effective, trigger
// Scheduled) so an instance opens when a classification or a rating changes with nobody pressing "Evaluate now". Like the
// sweep, the pass's connection carries no person: personnel.ResolveActor attributes its writes to the platform's System actor.
public sealed class ComplianceService(IConfiguration config, Catalog catalog, ILogger<ComplianceService> log) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var minutes = config.GetValue<int?>("Engine:ComplianceMinutes") ?? 60;
        if (minutes <= 0) { log.LogInformation("Compliance pass disabled (Engine:ComplianceMinutes = {Minutes})", minutes); return; }
        log.LogInformation("Compliance pass every {Minutes} min", minutes);
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(minutes));
        try
        {
            while (await timer.WaitForNextTickAsync(stoppingToken))
            {
                try
                {
                    await using var s = await SqlSession.OpenAsync(config["Database:ConnectionString"]!, null, stoppingToken);
                    var r = await new ComplianceEvaluator(s, catalog, log).EvaluateAsync(null, null, "Effective", "Scheduled", stoppingToken);
                    log.LogInformation("Compliance pass: {Rules} rule(s), {Subjects} subject(s), {Opened} opened, {Closed} closed, {Unknown} unknown, {Errors} error(s)",
                        r.Rules, r.Subjects, r.Opened, r.Closed, r.Unknown, r.Errors);
                }
                catch (Exception e) when (e is not OperationCanceledException) { log.LogError(e, "Compliance pass failed"); }
            }
        }
        catch (OperationCanceledException) { }
    }
}
