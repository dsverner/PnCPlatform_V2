using System.Security.Cryptography;
using System.Text;

namespace PnC.Api.Security;

// #218 (2026-09-21): a short-lived link to ONE stored file, so a desktop application can fetch it with the platform's identity.
// Word opens a document straight from a URL through the Office URI scheme (ms-word:ofv|u|<url>), but it fetches with its own
// HTTP client, which carries neither the page's DEV identity header nor, reliably, the browser's session. So the page asks
// the API for a link (POST /api/v1/files/{id}/link, authorised as the read itself is), and the link carries a token that
// names the file, the user and an expiry, signed with a key the server holds. On the GET, RequestUserMiddleware accepts a
// valid token as the identity of that user for that one file, and the read is authorised and logged to them as any other.
//   token = <expiresUnixSeconds>.<base64url(upn)>.<base64url(HMAC-SHA256(key, fileRowId|upn|expires))>
// The link is /api/v1/files/{id}/link/{token}/{file name}: measured 2026-09-21 on this laptop, Word requests nothing for a URL
// without a document extension, and drops a query string on its second round of requests — so both live in the path.
// The key comes from Files:LinkKey (ignored config, never source); when none is configured a random key is drawn at
// startup, so links outlive neither the process nor Files:LinkSeconds (default 90 s). A token opens its own file only.
public sealed class FileLinkTokens
{
    private readonly byte[] _key;
    public int LifetimeSeconds { get; }
    public bool KeyFromConfig { get; }

    public FileLinkTokens(IConfiguration config)
    {
        var configured = config["Files:LinkKey"];
        KeyFromConfig = !string.IsNullOrWhiteSpace(configured);
        _key = KeyFromConfig ? SHA256.HashData(Encoding.UTF8.GetBytes(configured!)) : RandomNumberGenerator.GetBytes(32);
        LifetimeSeconds = int.TryParse(config["Files:LinkSeconds"], out var s) && s is > 0 and <= 3600 ? s : 90;
    }

    public (string Token, DateTimeOffset ExpiresAt) Issue(Guid fileRowId, string upn)
    {
        var expires = DateTimeOffset.UtcNow.AddSeconds(LifetimeSeconds);
        var exp = expires.ToUnixTimeSeconds();
        var mac = Sign(fileRowId, upn, exp);
        return ($"{exp}.{B64(Encoding.UTF8.GetBytes(upn))}.{B64(mac)}", expires);
    }

    /// <summary>The user the token names, when it is intact, unexpired and issued for this very file; otherwise null.</summary>
    public string? Read(Guid fileRowId, string? token)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 600) return null;
        var parts = token.Split('.');
        if (parts.Length != 3 || !long.TryParse(parts[0], out var exp)) return null;
        if (DateTimeOffset.FromUnixTimeSeconds(exp) < DateTimeOffset.UtcNow) return null;
        byte[] upnBytes, mac;
        try { upnBytes = UnB64(parts[1]); mac = UnB64(parts[2]); } catch (FormatException) { return null; }
        var upn = Encoding.UTF8.GetString(upnBytes);
        if (upn.Length == 0 || upn.Length > 200 || upn.Any(char.IsControl)) return null;
        var expected = Sign(fileRowId, upn, exp);
        return CryptographicOperations.FixedTimeEquals(expected, mac) ? upn : null;
    }

    /// <summary>The file id and the token on a linked-file request, when it is one (GET or HEAD /api/v1/files/{id}/link/{token}/{name}).</summary>
    public static bool TryGetFileRequest(HttpRequest request, out Guid fileRowId, out string? token)
    {
        fileRowId = Guid.Empty; token = null;
        if (!HttpMethods.IsGet(request.Method) && !HttpMethods.IsHead(request.Method)) return false;
        var m = LinkPath.Match(request.Path.Value ?? "");
        if (!m.Success || !Guid.TryParse(m.Groups[1].Value, out fileRowId)) return false;
        token = m.Groups[2].Value;
        return true;
    }
    private static readonly System.Text.RegularExpressions.Regex LinkPath = new(@"^/api/v1/files/([0-9a-fA-F-]{36})/link/([A-Za-z0-9_.-]{1,600})/[^/]+$", System.Text.RegularExpressions.RegexOptions.Compiled);

    private byte[] Sign(Guid fileRowId, string upn, long exp) => HMACSHA256.HashData(_key, Encoding.UTF8.GetBytes($"{fileRowId:D}|{upn}|{exp}"));
    private static string B64(byte[] b) => Convert.ToBase64String(b).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    private static byte[] UnB64(string s)
    {
        var t = s.Replace('-', '+').Replace('_', '/');
        return Convert.FromBase64String(t.PadRight(t.Length + (4 - t.Length % 4) % 4, '='));
    }
}
