using System.Globalization;

namespace PnC.Formula;

/// <summary>The absence of a value (FORMULA-GRAMMAR.md §5). A singleton; never equal to anything but itself.</summary>
public sealed class Unknown
{
    public static readonly Unknown Value = new();
    private Unknown() { }
    public override string ToString() => "UNKNOWN";
}

/// <summary>A number with its unit and base.</summary>
public sealed record Quantity(decimal Value, string? Unit = null, string? Base = null)
{
    public override string ToString() => $"{Values.DecText(Value)}{(Unit is null ? "" : " " + Unit)}{(Base is null ? "" : "@" + Base)}";
}

/// <summary>A duration: y mo w d h, or any Time-dimension unit.</summary>
public sealed record Duration(decimal N, string Unit)
{
    /// <summary>Seconds; null for calendar units (y, mo).</summary>
    public decimal? Seconds() => Unit switch
    {
        "w" => N * 604800m,
        "d" => N * 86400m,
        "h" => N * 3600m,
        "y" or "mo" => null,
        _ => Units.ToBase(N, Unit).value,
    };
}

/// <summary>An entity reference: the id (text) and the subject kind.</summary>
public sealed record Ref(string Id, string Kind);

public static class Values
{
    /// <summary>The authoring offset for a date literal without one (the platform's configured offset).</summary>
    public static readonly TimeSpan DefaultOffset = TimeSpan.FromHours(-3);

    public static bool IsUnknown(object? v) => v is null || ReferenceEquals(v, Unknown.Value);

    /// <summary>Decimal text without trailing zeros, as Python's _dec_str.</summary>
    public static string DecText(decimal d)
    {
        var s = d.ToString("0.############################", CultureInfo.InvariantCulture);
        if (s == "-0" || s == "") s = "0";
        return s;
    }

    public static decimal ParseDecimal(string s) => decimal.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);

    /// <summary>The four literal forms: date, date-time, with seconds/fraction, with offset or Z.</summary>
    public static DateTimeOffset ParseDateTime(string s)
    {
        if (s.Length == 10)
            return new DateTimeOffset(DateTime.ParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None), DefaultOffset);
        s = s.EndsWith('Z') ? s[..^1] + "+00:00" : s;
        bool hasOffset = s.Length > 6 && (s[^6] == '+' || s[^6] == '-') && s[^3] == ':';
        if (hasOffset)
            return DateTimeOffset.ParseExact(s, new[] { "yyyy-MM-ddTHH:mmzzz", "yyyy-MM-ddTHH:mm:sszzz", "yyyy-MM-ddTHH:mm:ss.FFFFFFFzzz" }, CultureInfo.InvariantCulture, DateTimeStyles.None);
        var local = DateTime.ParseExact(s, new[] { "yyyy-MM-ddTHH:mm", "yyyy-MM-ddTHH:mm:ss", "yyyy-MM-ddTHH:mm:ss.FFFFFFF" }, CultureInfo.InvariantCulture, DateTimeStyles.None);
        return new DateTimeOffset(local, DefaultOffset);
    }

    /// <summary>Python's isoformat: seconds always, fraction only when non-zero, offset +HH:MM.</summary>
    public static string FormatDateTime(DateTimeOffset d)
    {
        var frac = d.Ticks % TimeSpan.TicksPerSecond;
        var core = frac == 0
            ? d.ToString("yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture)
            : d.ToString("yyyy-MM-ddTHH:mm:ss.ffffff", CultureInfo.InvariantCulture);
        var off = d.Offset;
        var sign = off < TimeSpan.Zero ? "-" : "+";
        off = off.Duration();
        return core + sign + off.Hours.ToString("00", CultureInfo.InvariantCulture) + ":" + off.Minutes.ToString("00", CultureInfo.InvariantCulture);
    }

    public static string TextOf(object v) => v switch
    {
        Quantity q => DecText(q.Value),
        bool b => b ? "true" : "false",
        DateTimeOffset d => FormatDateTime(d),
        Duration du => $"{DecText(du.N)} {du.Unit}",
        _ => v.ToString() ?? "",
    };

    /// <summary>Calendar arithmetic for y/mo (day clamped to the month), exact seconds otherwise.</summary>
    public static DateTimeOffset AddDuration(DateTimeOffset d, Duration dur)
    {
        if (dur.Unit is "y" or "mo")
        {
            var totalMonths = dur.N * (dur.Unit == "y" ? 12 : 1);
            var months = (int)decimal.Truncate(totalMonths);
            var frac = totalMonths - months;
            var m0 = d.Month - 1 + months;
            var y = d.Year + (int)Math.Floor(m0 / 12.0);
            var m = ((m0 % 12) + 12) % 12;
            var day = Math.Min(d.Day, DateTime.DaysInMonth(y, m + 1));
            var outDate = new DateTimeOffset(y, m + 1, day, d.Hour, d.Minute, d.Second, d.Millisecond, d.Offset).AddTicks(d.Ticks % TimeSpan.TicksPerMillisecond);
            return frac == 0 ? outDate : outDate.AddDays((double)frac * 30);
        }
        var secs = dur.Seconds() ?? throw new InvalidOperationException("calendar duration");
        return d.AddSeconds((double)secs);
    }
}
