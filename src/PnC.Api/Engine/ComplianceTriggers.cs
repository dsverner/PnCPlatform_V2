using System.Text.Json.Nodes;
using PnC.Api.Data;

namespace PnC.Api.Engine;

// #214 (2026-09-20): compliance evaluates itself. After a write through a procedure in this table the API leaves an
// evaluation request (compliance.RequestEvaluation) naming the subject whose facts changed; the compliance worker
// (ComplianceService) takes it within seconds, expands it to the devices affected (compliance.ExpandEvaluationRequests) and runs an
// Effective pass over them. One table, one paragraph: the procedure → how the subject is found in what was written.
//   Body(kind, key)        the id is in the request body under `key`; `kind` is fixed, or "$SubjectKind" = the body's own
//   Lookup(kind, sql)      the body carries only an EntityId (a _Revise / _SoftDelete): the subject is read from the table
//   All                    a rule, formula or derivation approved: every candidate device (trigger RuleApproved)
// A write made in SQL directly, a seed or a migration leaves no request; the hourly pass covers those.
public static class ComplianceTriggers
{
    sealed record Trigger(string Kind, string? Key, string? Sql);

    static readonly Dictionary<string, Trigger> Map = new(StringComparer.OrdinalIgnoreCase)
    {
        // classifications: the device's own, the protected element's, the bus's, a node's up the tree
        ["asset.RecordClassification"]        = new("$SubjectKind", "SubjectEntityId", null),
        ["asset.Classification_Add"]          = new("$SubjectKind", "SubjectEntityId", null),
        ["asset.Classification_Revise"]       = new("$SubjectKind", "SubjectEntityId", null),
        ["asset.Classification_SoftDelete"]   = new("$Lookup", "EntityId", "SELECT TOP (1) SubjectKind, SubjectEntityId FROM asset.Classification WHERE EntityId = @id ORDER BY RowSeq DESC"),
        // ratings and terminals of the protected element
        ["asset.RecordAssetRating"]           = new("Asset", "AssetEntityId", null),
        ["asset.AssetRating_Add"]             = new("Asset", "AssetEntityId", null),
        ["asset.AssetRating_Revise"]          = new("Asset", "AssetEntityId", null),
        ["asset.AssetRating_SoftDelete"]      = new("$Lookup", "EntityId", "SELECT TOP (1) N'Asset' AS SubjectKind, AssetEntityId AS SubjectEntityId FROM asset.AssetRating WHERE EntityId = @id ORDER BY RowSeq DESC"),
        ["asset.AssetTerminal_Add"]           = new("Asset", "AssetEntityId", null),
        ["asset.AssetTerminal_Revise"]        = new("Asset", "AssetEntityId", null),
        ["asset.AssetTerminal_SoftDelete"]    = new("$Lookup", "EntityId", "SELECT TOP (1) N'Asset' AS SubjectKind, AssetEntityId AS SubjectEntityId FROM asset.AssetTerminal WHERE EntityId = @id ORDER BY RowSeq DESC"),
        // where the device stands (its location's rating, its position's functions, its protects walk)
        ["asset.PlaceAsset"]                  = new("Asset", "AssetEntityId", null),
        ["asset.Placement_Add"]               = new("Asset", "AssetEntityId", null),
        ["asset.Placement_Revise"]            = new("Asset", "AssetEntityId", null),
        ["asset.Placement_SoftDelete"]        = new("$Lookup", "EntityId", "SELECT TOP (1) N'Asset' AS SubjectKind, AssetEntityId AS SubjectEntityId FROM asset.Placement WHERE EntityId = @id ORDER BY RowSeq DESC"),
        // the settings in service (device.settings.<Code>)
        ["document.SetInService"]             = new("$Lookup", "RevisionRowId", "SELECT TOP (1) N'Device' AS SubjectKind, DeviceEntityId AS SubjectEntityId FROM document.vConfigurationFile WHERE RevisionRowId = @id"),
        // the scheme: its members and what it protects
        ["scheme.AddSchemeMember"]            = new("Scheme", "SchemeEntityId", null),
        ["scheme.SchemeMember_Add"]           = new("Scheme", "SchemeEntityId", null),
        ["scheme.SchemeMember_Revise"]        = new("Scheme", "SchemeEntityId", null),
        ["scheme.SchemeMember_SoftDelete"]    = new("$Lookup", "EntityId", "SELECT TOP (1) N'Scheme' AS SubjectKind, SchemeEntityId AS SubjectEntityId FROM scheme.SchemeMember WHERE EntityId = @id ORDER BY RowSeq DESC"),
        ["scheme.SchemeProtects_Add"]         = new("Scheme", "SchemeEntityId", null),
        ["scheme.SchemeProtects_Revise"]      = new("Scheme", "SchemeEntityId", null),
        ["scheme.SchemeProtects_SoftDelete"]  = new("$Lookup", "EntityId", "SELECT TOP (1) N'Scheme' AS SubjectKind, SchemeEntityId AS SubjectEntityId FROM scheme.SchemeProtects WHERE EntityId = @id ORDER BY RowSeq DESC"),
        // the elements in service at a position (device.functions — PRC-023 Attachment A)
        ["scheme.CommissionedFunction_Add"]        = new("Node", "ProtectionFunctionNodeEntityId", null),
        ["scheme.CommissionedFunction_Revise"]     = new("Node", "ProtectionFunctionNodeEntityId", null),
        ["scheme.CommissionedFunction_SoftDelete"] = new("$Lookup", "EntityId", "SELECT TOP (1) N'Node' AS SubjectKind, ProtectionFunctionNodeEntityId AS SubjectEntityId FROM scheme.CommissionedFunction WHERE EntityId = @id ORDER BY RowSeq DESC"),
        // a rule, formula or derivation approved: everything (the lookup answers All only for those kinds)
        ["config.ApproveDefinitionVersion"]   = new("$Lookup", "VersionRowId", "SELECT TOP (1) CASE WHEN d.DefinitionKind IN (N'Program.ObligationRule', N'Program.Formula', N'Program.ClassificationDerivation') THEN N'All' END AS SubjectKind, CONVERT(UNIQUEIDENTIFIER, NULL) AS SubjectEntityId FROM config.DefinitionVersion v JOIN config.Definition d ON d.EntityId = v.DefinitionEntityId WHERE v.RowId = @id"),
    };

    /// <summary>The subject kinds compliance.RequestEvaluation accepts; a classification on a Scheme subject maps to Scheme, a Node to Node, an Asset to Asset.</summary>
    static readonly HashSet<string> Kinds = new(StringComparer.Ordinal) { "Device", "Asset", "Node", "Scheme", "All" };

    /// <summary>After a successful procedure call: leave the evaluation request the write calls for, on the same session (the
    /// writer's actor). Never fails the write — a request that could not be left is logged, and the hourly pass stands in.</summary>
    public static async Task AfterWriteAsync(ProcInfo proc, JsonObject body, SqlSession s, Catalog catalog, ILogger log, CancellationToken ct)
    {
        if (!Map.TryGetValue(proc.Key, out var t)) return;
        try
        {
            var (kind, id) = await ResolveAsync(t, body, s, ct);
            if (kind is null || !Kinds.Contains(kind) || (kind != "All" && id is null)) return;
            await RequestAsync(s, catalog, kind, id, proc.Key, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            log.LogWarning(e, "Compliance: no evaluation request could be left after {Proc}", proc.Key);
        }
    }

    /// <summary>Leave a request directly (the process endpoints: a step commit or a transition whose instance subject is a device).</summary>
    public static async Task RequestAsync(SqlSession s, Catalog catalog, string kind, Guid? id, string reason, CancellationToken ct)
    {
        var p = catalog.Procedure("compliance", "RequestEvaluation") ?? throw new InvalidOperationException("compliance.RequestEvaluation is not in the catalogue.");
        await s.ExecuteProcedureAsync(p, new JsonObject { ["SubjectKind"] = kind, ["SubjectEntityId"] = id?.ToString(), ["Reason"] = reason }, ct);
    }

    /// <summary>The process endpoints (#214): a step commit or a transition changes what a rule reads about the DEVICE the work is
    /// over — the instance's own subject when it is a device, else the work request's scope (#204: a root run is declared over
    /// the request; the request's scope is the device). Nothing is left when neither names a device.</summary>
    public static async Task RequestForWorkAsync(SqlSession s, Catalog catalog, string? subjectKind, Guid? subjectId, Guid? workRequestId, string reason, ILogger log, CancellationToken ct)
    {
        try
        {
            // the work's scope names the device as an Asset, or its position as a Node (the settings-change flows are declared over the
            // position); either expands to the device (compliance.ExpandEvaluationRequests: Asset → itself, Node → what stands at it)
            string? kind = subjectKind is "Device" or "Asset" ? "Asset" : subjectKind == "Node" ? "Node" : null; Guid? id = kind is null ? null : subjectId;
            if (kind is null && workRequestId is not null)
            {
                var row = (await s.RowsAsync("SELECT TOP (1) ScopeKind, ScopeEntityId FROM work.vWorkRequest WHERE EntityId = @w", new Dictionary<string, object?> { ["@w"] = workRequestId }, ct)).FirstOrDefault() as JsonObject;
                var sk = row?["ScopeKind"]?.GetValue<string>();
                if (sk is "Device" or "Asset" or "Node" && Guid.TryParse(row!["ScopeEntityId"]?.GetValue<string>(), out var g)) { kind = sk == "Node" ? "Node" : "Asset"; id = g; }
            }
            if (kind is not null && id is not null) await RequestAsync(s, catalog, kind, id, reason, ct);
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            log.LogWarning(e, "Compliance: no evaluation request could be left after {Reason}", reason);
        }
    }

    static async Task<(string? kind, Guid? id)> ResolveAsync(Trigger t, JsonObject body, SqlSession s, CancellationToken ct)
    {
        var raw = body.FirstOrDefault(kv => kv.Key.Equals(t.Key, StringComparison.OrdinalIgnoreCase)).Value?.ToString();
        if (!Guid.TryParse(raw, out var id)) return (null, null);
        switch (t.Kind)
        {
            case "$SubjectKind":
                return (body.FirstOrDefault(kv => kv.Key.Equals("SubjectKind", StringComparison.OrdinalIgnoreCase)).Value?.ToString(), id);
            case "$Lookup":
            {
                var row = (await s.RowsAsync(t.Sql!, new Dictionary<string, object?> { ["@id"] = id }, ct)).FirstOrDefault() as JsonObject;
                if (row is null) return (null, null);
                var kind = row["SubjectKind"]?.GetValue<string>();
                var sid = row["SubjectEntityId"]?.GetValue<string>();
                return (kind, Guid.TryParse(sid, out var g) ? g : null);
            }
            default:
                return (t.Kind, id);
        }
    }
}
