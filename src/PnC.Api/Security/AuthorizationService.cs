using System.Text.Json;
using PnC.Api.Data;
using PnC.Api.Endpoints;

namespace PnC.Api.Security;

// docs/design/API.md §5. One decision per request: security.fHasPermission. Roles, grants,
// delegations and scope are the function's business; nothing is evaluated here. A refusal is
// written to audit.ActionLog as AccessRefused before the 403 leaves.

public sealed class AuthorizationService
{
    public async Task RequireAsync(SqlSession session, RequestUser user, string permissionCode, string? subjectKind, Guid? subjectEntityId,
        string operation, string host, CancellationToken ct)
    {
        var allowed = await session.ScalarAsync<bool>(
            "SELECT [security].[fHasPermission](@u, @p, @k, @s, SYSDATETIMEOFFSET())",
            new Dictionary<string, object?> { ["@u"] = user.UserEntityId, ["@p"] = permissionCode, ["@k"] = subjectKind, ["@s"] = subjectEntityId }, ct);
        if (allowed) return;

        var detail = JsonSerializer.Serialize(new { operation, permission = permissionCode, subjectKind, subjectEntityId, host });
        // @ActorId is not passed: personnel.ResolveActor attributes the refusal to the session's own identity.
        await session.ExecAsync(
            "EXEC [audit].[LogAction] @ActionKindCode = N'AccessRefused', @Detail = @d",
            new Dictionary<string, object?> { ["@d"] = detail }, ct);
        throw new ApiException(403, "forbidden", $"{permissionCode} is not held for this subject.");
    }

    /// <summary>
    /// A list read (IDENTITY.md §5): does the user hold the permission in any scope? The rows themselves are then
    /// scoped by security.fReadableSubjects. A refusal is logged like any other.
    /// </summary>
    public async Task RequireHeldAsync(SqlSession session, RequestUser user, string permissionCode, string operation, string host, CancellationToken ct)
    {
        var held = await session.ScalarAsync<bool>(
            "SELECT [security].[fHoldsPermission](@u, @p, SYSDATETIMEOFFSET())",
            new Dictionary<string, object?> { ["@u"] = user.UserEntityId, ["@p"] = permissionCode }, ct);
        if (held) return;
        var detail = JsonSerializer.Serialize(new { operation, permission = permissionCode, subjectKind = (string?)null, subjectEntityId = (Guid?)null, host });
        await session.ExecAsync("EXEC [audit].[LogAction] @ActionKindCode = N'AccessRefused', @Detail = @d", new Dictionary<string, object?> { ["@d"] = detail }, ct);
        throw new ApiException(403, "forbidden", $"{permissionCode} is not held in any scope.");
    }
}
