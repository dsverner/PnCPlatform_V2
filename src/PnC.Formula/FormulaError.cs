namespace PnC.Formula;

/// <summary>
/// An authoring-time error of the formula language (FORMULA-GRAMMAR.md §10). Evaluation never throws on data;
/// it yields <see cref="Unknown"/>. <see cref="Code"/> is the taxonomy value the conformance suite compares.
/// </summary>
public sealed class FormulaException : Exception
{
    public string Code { get; }
    public int? Position { get; }

    public FormulaException(string code, string message, int? position = null)
        : base($"{code}: {message}" + (position is null ? "" : $" (at {position})"))
    {
        Code = code;
        Position = position;
    }
}

/// <summary>The error codes of FORMULA-GRAMMAR.md §10.</summary>
public static class ErrorCodes
{
    public const string Syntax = "syntax";
    public const string UnknownFact = "unknown_fact";
    public const string UnknownParameter = "unknown_parameter";
    public const string ParameterType = "parameter_type";
    public const string TypeMismatch = "type_mismatch";
    public const string DimensionMismatch = "dimension_mismatch";
    public const string MissingUnit = "missing_unit";
    public const string UnknownUnit = "unknown_unit";
    public const string BaseMismatch = "base_mismatch";
    public const string UnknownFunction = "unknown_function";
    public const string Arity = "arity";
    public const string UnboundVariable = "unbound_variable";
    public const string NotDeterministic = "not_deterministic";
    public const string ResultType = "result_type";
    public const string InputsMismatch = "inputs_mismatch";
    public const string EnumerationValue = "enumeration_value";
    public const string GrammarVersion = "grammar_version";
}
