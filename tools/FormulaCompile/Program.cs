using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Formula;

// usage: FormulaCompile <spec.json>
//   spec: {"items":[{"id":"…","kind":"expression"|"cadence","text":"…"}]}
//   out : {"<id>":{"ast":<node>,"canonical":"<canonical text>","facts":[…]} | {"error":"…"}} on stdout
// A failure to parse is reported per item, never silently dropped: the generator refuses to write a seed with an error.

if (args.Length != 1) { Console.Error.WriteLine("usage: FormulaCompile <spec.json>"); return 2; }
var spec = (JsonObject)JsonNode.Parse(File.ReadAllText(args[0]))!;
var outp = new JsonObject();
var failed = 0;
foreach (var item in (JsonArray)spec["items"]!)
{
    var o = (JsonObject)item!;
    var id = o["id"]!.GetValue<string>();
    var text = o["text"]!.GetValue<string>();
    var kind = o["kind"]?.GetValue<string>() ?? "expression";
    try
    {
        var ast = kind == "cadence" ? Parser.ParseCadence(text) : Parser.Parse(text);
        var facts = new JsonArray(Canonical.FactNames(ast).OrderBy(x => x, StringComparer.Ordinal).Select(x => (JsonNode)JsonValue.Create(x)).ToArray());
        outp[id] = new JsonObject { ["ast"] = ast, ["canonical"] = Canonical.ToCanonical(ast), ["facts"] = facts };
    }
    catch (Exception e) { outp[id] = new JsonObject { ["error"] = e.Message }; failed++; }
}
Console.Out.Write(outp.ToJsonString(new JsonSerializerOptions { WriteIndented = false, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
return failed == 0 ? 0 : 1;
