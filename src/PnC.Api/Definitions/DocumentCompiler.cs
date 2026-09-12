using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Formula;

namespace PnC.Api.Definitions;

// PROCEDURE-ENGINE §3, §7, §8 (W3, decision #100). The API does the part of authoring that only the grammar library can
// do: it validates the authored document against its JSON Schema, parses every expression, type-checks it against the
// live fact catalogue extended with what the document itself declares (its roles, inputs, captured fields, produced
// entities), replaces the text with its canonical AST and emits the canonical document text that process.Add*Version
// stores and hashes. Every structural rule (unique ids, declared roles, workflow transitions, the C1 check…) is the
// database's — process.ValidateProcedureDocument — and is not repeated here.

public sealed record CompileError(string Path, string Code, string Message);

public sealed class CompileException(IReadOnlyList<CompileError> errors) : Exception("document_invalid")
{
    public IReadOnlyList<CompileError> Errors { get; } = errors;
}

/// <summary>compliance.vFactCatalogue as the checker's catalogue, with ref.Unit loaded into the library's unit table.</summary>
public static class LiveCatalogue
{
    public static async Task<Catalogue> LoadAsync(SqlSession s, CancellationToken ct)
    {
        var units = await s.RowsAsync("SELECT UnitCode, Dimension, BaseUnitCode, ToBaseFactor FROM ref.vUnit", new Dictionary<string, object?>(), ct);
        Units.LoadUnits(units.Select(u => (JsonObject)u!).Select(u =>
            (u["UnitCode"]!.GetValue<string>(), u["Dimension"]!.GetValue<string>(), u["BaseUnitCode"]?.GetValue<string>(), u["ToBaseFactor"]?.GetValue<decimal>())));
        var rows = await s.RowsAsync("SELECT FactName, DataType, UnitCode, Base, SubjectKind, ReferenceKind, Parameters FROM compliance.vFactCatalogue", new Dictionary<string, object?>(), ct);
        var facts = new List<FactInfo>();
        foreach (var r in rows.Select(x => (JsonObject)x!))
        {
            var dt = r["DataType"]?.GetValue<string>() ?? "Text";
            var refKind = r["ReferenceKind"]?.GetValue<string>();
            FormulaType type = dt switch
            {
                "Integer" or "Decimal" => FormulaType.Num(r["UnitCode"]?.GetValue<string>(), r["Base"]?.GetValue<string>()),
                "Boolean" => FormulaType.Bool,
                "DateTime" => FormulaType.Date,
                "Reference" => new FormulaType("ref", RefKind: refKind),
                "Set" => new FormulaType("set", Elem: refKind is null ? FormulaType.Num() : new FormulaType("ref", RefKind: refKind)),
                "Any" => FormulaType.UnknownT,          // typed by the document (step.capture), FORMULA-GRAMMAR §7
                _ => FormulaType.Text,
            };
            Dictionary<string, FormulaType>? ps = null;
            if (r["Parameters"]?.GetValue<string>() is { } pj && JsonNode.Parse(pj) is JsonArray pa)
                ps = pa.ToDictionary(p => p!.GetValue<string>(), p => p!.GetValue<string>() switch
                {
                    "open" or "accepted" => FormulaType.Bool,
                    "km" or "minutes" or "pass" => FormulaType.Num(),
                    _ => FormulaType.Text,
                }, StringComparer.Ordinal);
            facts.Add(new FactInfo(r["FactName"]!.GetValue<string>(), type, ps, r["SubjectKind"]?.GetValue<string>(), null, refKind));
        }
        return new Catalogue(facts);
    }
}

/// <summary>The live catalogue plus the names a procedure document declares: procedure.&lt;produces.as&gt; and input.&lt;name&gt;.</summary>
public sealed class DocumentCatalogue(ICatalogue live, IReadOnlyDictionary<string, FactInfo> declared) : ICatalogue
{
    public FactInfo? Lookup(string name, string? subjectKind = null) => declared.TryGetValue(name, out var f) ? f : live.Lookup(name, subjectKind);
}

public static class DocumentCompiler
{
    /// <summary>A capture / input value type (procedure.schema.json valueType) as a formula type.</summary>
    public static FormulaType ValueType(JsonObject vt) => vt["type"]?.GetValue<string>() switch
    {
        "num" => FormulaType.Num(vt["unit"]?.GetValue<string>(), vt["base"]?.GetValue<string>()),
        "text" => FormulaType.Text,
        "bool" => FormulaType.Bool,
        "date" => FormulaType.Date,
        "dur" => FormulaType.Dur,
        "ref" => new FormulaType("ref", RefKind: vt["refKind"]?.GetValue<string>()),
        "set" => new FormulaType("set", Elem: new FormulaType("ref", RefKind: vt["refKind"]?.GetValue<string>())),
        _ => FormulaType.UnknownT,                      // file: a document.File reference, not an expression value
    };

    /// <summary>
    /// Compiles an authored document in place: every expression site becomes canonical AST; the result is the canonical
    /// text. Throws <see cref="CompileException"/> with every error found (schema first, then expressions).
    /// </summary>
    public static string Compile(JsonObject doc, SchemaCheck schema, ICatalogue live, IReadOnlyDictionary<string, string> workflowSubjectKinds)
    {
        var errors = new List<CompileError>();
        foreach (var v in schema.Validate(doc)) errors.Add(new(v.Path, "schema", v.Message));
        if (errors.Count > 0) throw new CompileException(errors);

        var kind = doc["kind"]!.GetValue<string>();
        var subjectKind = doc["subjectKind"]?.GetValue<string>();

        // what the document declares
        var declared = new Dictionary<string, FactInfo>(StringComparer.Ordinal);
        if (doc["inputs"] is JsonObject inputs)
            foreach (var (n, vt) in inputs) declared[$"input.{n}"] = new FactInfo($"input.{n}", ValueType((JsonObject)vt!));
        if (kind == "procedure") WalkBlocks(doc["body"], b =>
        {
            if (b["produces"] is JsonObject p && p["as"]?.GetValue<string>() is { } name)
                declared[$"procedure.{name}"] = new FactInfo($"procedure.{name}", new FormulaType("ref", RefKind: p["kind"]?.GetValue<string>()), null, null, null, p["kind"]?.GetValue<string>());
        });
        var cat = new DocumentCatalogue(live, declared);

        void Site(JsonObject owner, string key, string path, string expect, string? sk, IReadOnlyDictionary<string, FormulaType>? env = null)
        {
            if (owner[key] is not JsonNode n) return;
            JsonObject ast;
            try
            {
                ast = n is JsonValue v && v.TryGetValue<string>(out var text) ? Parser.Parse(text) : (JsonObject)n.DeepClone();
                var t = Checker.Check(ast, cat, env, sk);
                var ok = expect switch
                {
                    "bool" => t.Kind is "bool" or "unknown",
                    "set" => t.Kind is "set" or "unknown",
                    "ref" => t.Kind is "ref" or "unknown",
                    _ => true,
                };
                if (!ok) errors.Add(new(path, ErrorCodes.ResultType, $"must be {expect}, is {t}"));
            }
            catch (FormulaException e) { errors.Add(new(path, e.Code, e.Message)); return; }
            owner[key] = Canonical.Order(ast);
        }

        // roles: competency over person.* facts, subject Person
        if (doc["roles"] is JsonObject roles)
            foreach (var (alias, r) in roles) Site((JsonObject)r!, "requires", $"$.roles.{alias}.requires", "bool", "Person");
        if (doc["inputs"] is JsonObject inputs2)
            foreach (var (n, vt) in inputs2) Site((JsonObject)vt!, "validate", $"$.inputs.{n}.validate", "bool", subjectKind, new Dictionary<string, FormulaType> { ["value"] = ValueType((JsonObject)vt!) });

        if (kind == "procedure")
            WalkBlocks(doc["body"], (b, path, sk) =>
            {
                switch (b["block"]?.GetValue<string>())
                {
                    case "step":
                        Site(b, "precondition", $"{path}.precondition", "bool", sk);
                        if (b["capture"] is JsonObject cap)
                            foreach (var (f, vt) in cap)
                                Site((JsonObject)vt!, "validate", $"{path}.capture.{f}.validate", "bool", sk, new Dictionary<string, FormulaType> { ["value"] = ValueType((JsonObject)vt!) });
                        if (b["advances"] is JsonObject adv)
                        {
                            Site(adv, "subject", $"{path}.advances.subject", "ref", sk);
                            // the subject's kind must be the workflow's (§2: "a subject of the right kind")
                            var wf = adv["workflow"]?.GetValue<string>() ?? "";
                            if (adv["subject"] is JsonObject sAst && workflowSubjectKinds.TryGetValue(wf, out var wfKind))
                            {
                                var t = SafeType(sAst, cat, sk);
                                if (t is { Kind: "ref" } && t.RefKind is not null && t.RefKind != wfKind)
                                    errors.Add(new($"{path}.advances.subject", ErrorCodes.TypeMismatch, $"names a {t.RefKind}; workflow {wf} governs a {wfKind}"));
                            }
                        }
                        if (b["due"] is JsonObject due && due["cadence"] is JsonValue cv && cv.TryGetValue<string>(out var ctext))
                        {
                            try { due["cadence"] = Canonical.Order(Parser.ParseCadence(ctext)); }
                            catch (FormulaException e) { errors.Add(new($"{path}.due.cadence", e.Code, e.Message)); }
                        }
                        break;
                    case "foreach": Site(b, "over", $"{path}.over", "set", sk); break;
                    case "repeat": Site(b, "until", $"{path}.until", "bool", sk); break;
                    case "hold": Site(b, "until", $"{path}.until", "bool", sk); break;
                    case "choice":
                        if (b["cases"] is JsonArray cases)
                            for (var i = 0; i < cases.Count; i++) Site((JsonObject)cases[i]!, "when", $"{path}.cases[{i}].when", "bool", sk);
                        break;
                    case "parallel":
                        if (b["branches"] is JsonArray branches)
                            for (var i = 0; i < branches.Count; i++) Site((JsonObject)branches[i]!, "applies", $"{path}.branches[{i}].applies", "bool", sk);
                        break;
                    case "call":
                        Site(b, "subject", $"{path}.subject", "ref", sk);
                        if (b["bind"] is JsonObject bind)
                            foreach (var (n, _) in bind.ToList()) Site(bind, n, $"{path}.bind.{n}", "any", sk);
                        break;
                }
            }, "$.body", subjectKind);
        else if (kind == "workflow" && doc["transitions"] is JsonArray transitions)
            for (var i = 0; i < transitions.Count; i++)
                if (((JsonObject)transitions[i]!)["requires"] is JsonArray reqs)
                    for (var j = 0; j < reqs.Count; j++) Site((JsonObject)reqs[j]!, "when", $"$.transitions[{i}].requires[{j}].when", "bool", subjectKind);

        if (errors.Count > 0) throw new CompileException(errors);
        return Canonical.ToCanonical(doc);
    }

    private static FormulaType? SafeType(JsonObject ast, ICatalogue cat, string? sk)
    {
        try { return Checker.Check(ast, cat, null, sk); } catch (FormulaException) { return null; }
    }

    private static void WalkBlocks(JsonNode? node, Action<JsonObject> visit) => WalkBlocks(node, (b, _, _) => visit(b), "$.body", null);

    /// <summary>Depth-first over the block tree; a foreach rebinds the subject kind for its body (§7 resolution scope).</summary>
    private static void WalkBlocks(JsonNode? node, Action<JsonObject, string, string?> visit, string path, string? subjectKind)
    {
        if (node is not JsonObject b) return;
        visit(b, path, subjectKind);
        switch (b["block"]?.GetValue<string>())
        {
            case "sequence":
                if (b["items"] is JsonArray items) for (var i = 0; i < items.Count; i++) WalkBlocks(items[i], visit, $"{path}.items[{i}]", subjectKind);
                break;
            case "parallel":
                if (b["branches"] is JsonArray br) for (var i = 0; i < br.Count; i++) WalkBlocks(((JsonObject)br[i]!)["body"], visit, $"{path}.branches[{i}].body", subjectKind);
                break;
            case "choice":
                if (b["cases"] is JsonArray cs) for (var i = 0; i < cs.Count; i++) WalkBlocks(((JsonObject)cs[i]!)["body"], visit, $"{path}.cases[{i}].body", subjectKind);
                WalkBlocks(b["else"], visit, $"{path}.else", subjectKind);
                break;
            case "foreach":
                WalkBlocks(b["body"], visit, $"{path}.body", b["subjectKind"]?.GetValue<string>() ?? subjectKind);
                break;
            case "repeat":
                WalkBlocks(b["body"], visit, $"{path}.body", subjectKind);
                break;
        }
    }
}
