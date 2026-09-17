using System.Text.RegularExpressions;

namespace PnC.Formula;

/// <summary>A token: kind (ws, date, num, qty, text, atvar, dollar, name, kw, unit, op, eof), value, position.</summary>
public sealed record Tok(string Kind, string Value, int Pos, (string val, string unit, string? b)? Qty = null);

public static class Lexer
{
    public static readonly HashSet<string> Keywords = new(StringComparer.Ordinal)
    {
        "and", "or", "not", "in", "like", "matches", "is", "unknown", "at", "true", "false",
        "every", "from", "within", "of", "once", "offset", "effective", "event",
        "calendar_year", "calendar_quarter", "calendar_month",
    };

    static readonly Regex Token = new(
        @"\G(?:(?<ws>\s+|--[^\n]*)" +
        @"|(?<date>\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?)?)" +
        @"|(?<num>(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?)" +
        @"|(?<text>'(?:[^']|'')*')" +
        @"|(?<atvar>@[A-Za-z_][A-Za-z0-9_]*)" +
        @"|(?<dollar>\$[A-Za-z_][A-Za-z0-9_]*|\$)" +
        // a name may end in '%' directly attached (#171: SEL-221F zone-reach setting codes Z1%, Z2%, Z3%);
        // the '%' stays inside the final segment, so device.settings.Z3% is one fact name
        @"|(?<name>[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)*%?)" +
        @"|(?<unit>[Ω°%][A-Za-z]*)" +
        @"|(?<op>->|<=|>=|<>|[-+*/^=<>(),{}\[\]:.]))", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    static readonly Regex UnitAfterNum = new(@"\G\s*([A-Za-z°Ω%][A-Za-z°Ω%]*(?:/[A-Za-z]+)?)(@(Primary|Secondary|PerUnit))?", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    static readonly string[] Groups = { "ws", "date", "num", "text", "atvar", "dollar", "name", "unit", "op" };

    public static List<Tok> Tokenize(string text)
    {
        var outp = new List<Tok>();
        int i = 0, n = text.Length;
        while (i < n)
        {
            var m = Token.Match(text, i);
            if (!m.Success) throw new FormulaException(ErrorCodes.Syntax, $"unexpected character '{text[i]}'", i);
            string kind = Groups.First(g => m.Groups[g].Success);
            string val = m.Groups[kind].Value;
            if (kind == "ws") { i = m.Index + m.Length; continue; }
            if (kind == "num")
            {
                var um = UnitAfterNum.Match(text, m.Index + m.Length);
                if (um.Success && (Units.Table.ContainsKey(um.Groups[1].Value) || Units.DurationUnits.Contains(um.Groups[1].Value)))
                {
                    var u = um.Groups[1].Value;
                    // 'in' is a unit and a keyword: a unit only when directly attached (no space)
                    if (u == "in" && um.Groups[1].Index != m.Index + m.Length) { outp.Add(new Tok("num", val, i)); i = m.Index + m.Length; continue; }
                    outp.Add(new Tok("qty", val, i, (val, u, um.Groups[3].Success ? um.Groups[3].Value : null)));
                    i = um.Index + um.Length; continue;
                }
                outp.Add(new Tok("num", val, i)); i = m.Index + m.Length; continue;
            }
            if (kind == "name" && Keywords.Contains(val.ToLowerInvariant())) { outp.Add(new Tok("kw", val.ToLowerInvariant(), i)); i = m.Index + m.Length; continue; }
            outp.Add(new Tok(kind, val, i)); i = m.Index + m.Length;
        }
        outp.Add(new Tok("eof", "", n));
        return outp;
    }
}
