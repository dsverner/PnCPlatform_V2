namespace PnC.Formula;

/// <summary>Unit table: (dimension, base unit code, to-base factor). Mirrors ref.Unit; LoadUnits replaces it from the database.</summary>
public static class Units
{
    public sealed record UnitInfo(string Dimension, string? BaseUnit, decimal? ToBaseFactor);

    public static readonly Dictionary<string, UnitInfo> Table = new(StringComparer.Ordinal)
    {
        ["V"] = new("Voltage", null, null), ["kV"] = new("Voltage", "V", 1000m),
        ["A"] = new("Current", null, null), ["kA"] = new("Current", "A", 1000m),
        ["VA"] = new("ApparentPower", null, null), ["MVA"] = new("ApparentPower", "VA", 1000000m),
        ["W"] = new("Power", null, null), ["MW"] = new("Power", "W", 1000000m),
        ["Ah"] = new("Charge", null, null),
        ["Ω"] = new("Impedance", null, null),
        ["ratio"] = new("Ratio", null, null), ["%"] = new("Ratio", "ratio", 0.01m), ["pu"] = new("Ratio", "ratio", 1m),
        ["s"] = new("Time", null, null), ["ms"] = new("Time", "s", 0.001m), ["min"] = new("Time", "s", 60m),
        ["cycles"] = new("Time", null, null),
        ["Hz"] = new("Frequency", null, null),
        ["m"] = new("Length", null, null), ["ft"] = new("Length", "m", 0.3048m), ["in"] = new("Length", "m", 0.0254m),
        ["km"] = new("Length", "m", 1000m), ["mi"] = new("Length", "m", 1609.344m),
        ["°C"] = new("Temperature", null, null),
        ["deg"] = new("Angle", null, null),

        ["ohm/mi"] = new("Other", null, null),
    };

    public static readonly string[] DurationUnits = { "y", "mo", "w", "d", "h" };

    static readonly Dictionary<(string, string), string?> Products = new()
    {
        [("Voltage", "Current")] = "ApparentPower", [("Current", "Impedance")] = "Voltage", [("Energy", "Time")] = null,
    };
    static readonly Dictionary<(string, string), string> Quotients = new()
    {
        [("Voltage", "Current")] = "Impedance", [("Power", "Voltage")] = "Current", [("ApparentPower", "Voltage")] = "Current",
        [("Voltage", "Impedance")] = "Current", [("Energy", "Time")] = "Power", [("ApparentPower", "Current")] = "Voltage",
    };

    /// <summary>Replace the table from ref.Unit rows (UnitCode, Dimension, BaseUnitCode, ToBaseFactor).</summary>
    public static void LoadUnits(IEnumerable<(string code, string dimension, string? baseUnit, decimal? factor)> rows)
    {
        Table.Clear();
        foreach (var (code, dim, b, f) in rows) Table[code] = new(dim, b, f);
    }

    public static string? Dimension(string? u)
    {
        if (u is null) return null;
        if (!Table.TryGetValue(u, out var info)) throw new FormulaException(ErrorCodes.UnknownUnit, $"unit '{u}' is not in ref.Unit");
        return info.Dimension;
    }

    public static (decimal value, string unit) ToBase(decimal value, string u)
    {
        var info = Table[u];
        return info.BaseUnit is null ? (value, u) : (value * info.ToBaseFactor!.Value, info.BaseUnit);
    }

    /// <summary>Convert within a dimension; null when not convertible.</summary>
    public static decimal? Convert(decimal value, string from, string to)
    {
        if (from == to) return value;
        if (Dimension(from) != Dimension(to) || Dimension(from) == "Other") return null;
        var (v, b1) = ToBase(value, from);
        var (_, b2) = ToBase(1m, to);
        if (b1 != b2) return null;
        var f = Table[to].ToBaseFactor;
        return f is null ? v : v / f.Value;
    }

    public static string? BaseUnitOf(string dim)
    {
        foreach (var (code, info) in Table)
            if (info.Dimension == dim && info.BaseUnit is null) return code;
        return null;
    }

    /// <summary>Dimension of d1 * d2 or d1 / d2 as the checker names it; null = unnameable. Returns (found, dim).</summary>
    public static (bool found, string? dim) ProductDimension(string d1, string d2, string op)
    {
        if (op == "*")
        {
            if (Products.TryGetValue((d1, d2), out var p) && p is not null) return (true, p);
            if (Products.TryGetValue((d2, d1), out var q) && q is not null) return (true, q);
            // #171: Ratio is dimensionless, so it scales rather than combines — Ratio * X = X, X * Ratio = X
            if (d1 == "Ratio") return (true, d2);
            if (d2 == "Ratio") return (true, d1);
            return (false, null);
        }
        if (d2 == "Ratio" && d1 != "Ratio") return (true, d1);   // #171: X / Ratio = X (Ratio / Ratio stays dimensionless)
        return Quotients.TryGetValue((d1, d2), out var r) ? (true, r) : (false, null);
    }

    /// <summary>The unit of u1 (*|/) u2 for the evaluator (Python's _unit_product): null = dimensionless.</summary>
    public static string? UnitProduct(string? u1, string? u2, string op)
    {
        var d1 = u1 is null ? null : Dimension(u1);
        var d2 = u2 is null ? null : Dimension(u2);
        if (d2 is null) return u1;
        if (d1 is null) return op == "*" ? u2 : null;
        if (op == "/" && d1 == d2) return null;
        string? d;
        if (op == "*") { var (f, dim) = ProductDimension(d1, d2, "*"); d = f ? dim : null; }
        else
        {
            var (f, dim) = ProductDimension(d1, d2, "/");
            d = f ? dim : null;
            if (d is null && d1 == "Impedance" && d2 == "Length") return $"{u1}/{u2}";
        }
        return d is null ? null : BaseUnitOf(d);
    }
}
