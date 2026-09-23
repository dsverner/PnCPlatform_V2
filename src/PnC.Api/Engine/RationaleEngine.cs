using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using PnC.Api.Data;
using PnC.Api.Documents;
using PnC.Api.Endpoints;
using PnC.Formula;

namespace PnC.Api.Engine;

// #219 (2026-09-21): the structured rationale — one section per protective element. The owner: the engineer enters the values
// and the rationale once; the application makes the settings values, the settings file and the Word document from that entry;
// "a rational 'section' for each of the protective elements being used"; the settings that supervise an element handled
// explicitly. The template is a Program.Rationale definition (tools/rationale_sel221f.py; decision 78 keeps payloads to Program kinds): its characteristic
// definitions are the inputs, its payload the sections (formulas over line.*, device.*, input.*, value.*, setting.*; the statement
// with {placeholders}); the element map (the Relay Word definition, tools/relay_word_sel221f.py) gives each element its outputs,
// its owned settings and what supervises it (the manual's own logic, 2-18/2-24).
//   Load  — the record, its template, the map, the line (the scheme's, the stored pick, or the caller's), its facts, the stored inputs,
//           the last result. Apply — validate, evaluate the sections in map order, write every owned setting through
//           process.SetParsedSetting, store the inputs (document.SetRationaleValue), derive MTU/MRI/MTO from the elements' marks,
//           file rationale.json and rationale.docx on the Draft rationale revision (document.CreateRationale), log the act.
public static class RationaleEngine
{
    public sealed class State
    {
        public required JsonObject Record { get; init; }
        public Guid DefinitionEntityId { get; init; }
        public Guid TemplateVersionRowId { get; init; }
        public JsonObject? Template { get; init; }
        public JsonObject? Map { get; init; }
        public Dictionary<string, JsonObject> Defs { get; init; } = new(StringComparer.OrdinalIgnoreCase);
        public Guid? RationaleRevisionRowId { get; set; }
        public string? RationaleStatus { get; set; }
        public Dictionary<string, string> Stored { get; init; } = new(StringComparer.OrdinalIgnoreCase);
        public JsonObject? Line { get; set; }
        public string LineSource { get; set; } = "none";
        public Dictionary<string, object?> Facts { get; } = new(StringComparer.Ordinal);
        public List<string> Missing { get; } = new();
        public HashSet<string> Commissioned { get; } = new(StringComparer.OrdinalIgnoreCase);
        public JsonArray Files { get; set; } = new();
        public JsonObject? LastResult { get; set; }
    }

    static string S(JsonNode? n) => n?.ToString() ?? "";
    static Guid? G(JsonNode? n) => Guid.TryParse(n?.ToString(), out var g) ? g : null;
    static decimal? D(JsonNode? n) => n is null ? null : decimal.TryParse(n.ToString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? d : null;
    static string Dec(decimal d) => d.ToString("0.####", CultureInfo.InvariantCulture);

    public static async Task<State> LoadAsync(SqlSession s, Guid settingsRevision, Guid? lineOverride, CancellationToken ct)
    {
        var rec = (await s.RowsAsync("SELECT * FROM document.vSettingsRecord WHERE RevisionRowId = @r", new Dictionary<string, object?> { ["@r"] = settingsRevision }, ct)).FirstOrDefault() as JsonObject
            ?? throw new ApiException(404, "unknown_revision", "No settings record has that revision.");
        // the model's Effective rationale template
        var tpl = (await s.RowsAsync("""
            SELECT TOP (1) d.EntityId, dv.RowId, dv.PayloadText FROM config.vDefinition d
            JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId AND dv.Status = N'Effective'
            JOIN config.vDefinitionAppliesTo ap ON ap.DefinitionVersionRowId = dv.RowId AND ap.DimensionCode = N'Model' AND ap.ValueEntityId = @m
            WHERE d.DefinitionKind = N'Program.Rationale' ORDER BY dv.VersionNumber DESC
            """, new Dictionary<string, object?> { ["@m"] = G(rec["ModelId"]) ?? Guid.Empty }, ct)).FirstOrDefault() as JsonObject;
        var st = new State { Record = rec, DefinitionEntityId = G(tpl?["EntityId"]) ?? Guid.Empty, TemplateVersionRowId = G(tpl?["RowId"]) ?? Guid.Empty,
                             Template = tpl is null ? null : JsonNode.Parse(S(tpl["PayloadText"])) as JsonObject };
        if (st.Template is null) return st;
        var mapKey = S(st.Template["elementMap"]);
        var map = await s.ScalarAsync<string>("""
            SELECT TOP (1) dv.PayloadText FROM config.vDefinition d JOIN config.vDefinitionVersion dv ON dv.DefinitionEntityId = d.EntityId AND dv.Status = N'Effective'
            WHERE d.DefinitionKind = N'Program.RelayWord' AND d.DefinitionKey = @k ORDER BY dv.VersionNumber DESC
            """, new Dictionary<string, object?> { ["@k"] = mapKey }, ct);
        if (map is not null) st = Copy(st, JsonNode.Parse(map) as JsonObject);
        foreach (var d in await s.RowsAsync("SELECT RowId, CharacteristicKey, DataType, UnitCode, AllowedValuesDefinitionRowId FROM config.vCharacteristicDefinition WHERE DefinitionVersionRowId = @v",
                     new Dictionary<string, object?> { ["@v"] = st.TemplateVersionRowId }, ct))
            st.Defs[S(d!["CharacteristicKey"])] = (JsonObject)d!;
        // the rationale this revision has, its stored inputs, its files and last result
        var ra = (await s.RowsAsync("""
            SELECT TOP (1) r.RowId, r.Status FROM document.vRevisionLink l JOIN document.vRevision r ON r.RowId = l.RevisionRowId
            JOIN document.vRationale ra ON ra.RevisionRowId = r.RowId
            WHERE l.SubjectKind = N'DocumentRevision' AND l.SubjectEntityId = @rev AND l.LinkKind = N'About' ORDER BY r.CreatedAt DESC
            """, new Dictionary<string, object?> { ["@rev"] = settingsRevision }, ct)).FirstOrDefault() as JsonObject;
        if (ra is not null)
        {
            st.RationaleRevisionRowId = G(ra["RowId"]); st.RationaleStatus = S(ra["Status"]);
            foreach (var v in await s.RowsAsync("""
                SELECT cd.CharacteristicKey, v.TextValue, v.IntegerValue, v.DecimalValue, v.BooleanValue, v.ReferenceEntityId
                FROM document.vCharacteristicValue v JOIN config.vCharacteristicDefinition cd ON cd.RowId = v.CharacteristicDefinitionRowId
                WHERE v.HostRevisionRowId = @rr AND v.ValidTo IS NULL
                """, new Dictionary<string, object?> { ["@rr"] = st.RationaleRevisionRowId }, ct))
            {
                var o = (JsonObject)v!;
                var val = o["TextValue"]?.ToString() ?? o["ReferenceEntityId"]?.ToString() ?? (o["BooleanValue"] is null ? null : (o["BooleanValue"]!.GetValue<bool>() ? "Y" : "N"))
                          ?? (D(o["DecimalValue"]) is { } dd ? Dec(dd) : null) ?? o["IntegerValue"]?.ToString();
                if (val is not null) st.Stored[S(o["CharacteristicKey"])] = val;
            }
            st.Files = await s.RowsAsync("SELECT RowId, EntityId, FileName, MimeType, SizeBytes, FileStreamId FROM document.vFile WHERE RevisionRowId = @rr ORDER BY FileName",
                new Dictionary<string, object?> { ["@rr"] = st.RationaleRevisionRowId }, ct);
            var json = st.Files.LastOrDefault(f => IsRationaleFile(S(f?["FileName"]), ".json")) as JsonObject;   // the newest: the names are stamped
            if (json?["FileStreamId"] is not null)
            {
                var bytes = await s.ScalarAsync<byte[]>("SELECT file_stream FROM document.FileStore WHERE stream_id = @id", new Dictionary<string, object?> { ["@id"] = G(json["FileStreamId"]) }, ct);
                if (bytes is not null) try { st.LastResult = JsonNode.Parse(bytes) as JsonObject; } catch (JsonException) { }
            }
        }
        // the line: the caller's, else the stored pick, else the scheme's
        var device = G(rec["DeviceEntityId"]) ?? Guid.Empty;
        Guid? lineId = lineOverride; st.LineSource = lineOverride is null ? "none" : "chosen";
        if (lineId is null && st.Stored.TryGetValue("Line", out var stored) && Guid.TryParse(stored, out var sg)) { lineId = sg; st.LineSource = "stored"; }
        if (lineId is null)
        {
            var sch = (await s.RowsAsync("""
                SELECT TOP (1) COALESCE(t.AssetEntityId, p.PrimaryAssetEntityId) AS LineEntityId FROM scheme.vSchemeExpanded e
                JOIN scheme.vSchemeProtects p ON p.SchemeEntityId = e.SchemeEntityId
                LEFT JOIN asset.vAssetTerminalDetail t ON t.TerminalEntityId = p.AssetTerminalEntityId
                JOIN asset.vAsset a ON a.EntityId = COALESCE(t.AssetEntityId, p.PrimaryAssetEntityId) AND a.AssetTypeCode = N'Line'
                WHERE e.ResolvedDeviceEntityId = @d
                """, new Dictionary<string, object?> { ["@d"] = device }, ct)).FirstOrDefault() as JsonObject;
            lineId = G(sch?["LineEntityId"]); if (lineId is not null) st.LineSource = "scheme";
        }
        st.Facts["device.Name"] = S(rec["DeviceName"]); st.Facts["device.Station"] = S(rec["StationName"]);
        if (lineId is not null)
        {
            var line = (await s.RowsAsync("SELECT EntityId, Name, VoltageClassCode, Status FROM asset.vAsset WHERE EntityId = @l AND AssetTypeCode = N'Line'", new Dictionary<string, object?> { ["@l"] = lineId }, ct)).FirstOrDefault() as JsonObject;
            if (line is not null)
            {
                var terms = await s.RowsAsync("SELECT TerminalNo, StationName, StationNodeEntityId FROM asset.vAssetTerminalDetail WHERE AssetEntityId = @l ORDER BY TerminalNo", new Dictionary<string, object?> { ["@l"] = lineId }, ct);
                var here = G(rec["StationNodeEntityId"]);
                var near = terms.FirstOrDefault(t => G(t?["StationNodeEntityId"]) == here) as JsonObject ?? terms.FirstOrDefault() as JsonObject;
                var far = terms.FirstOrDefault(t => !ReferenceEquals(t, near)) as JsonObject;
                var kvText = new string(S(line["VoltageClassCode"]).TakeWhile(c => char.IsDigit(c) || c == '.').ToArray());
                st.Line = new JsonObject { ["EntityId"] = lineId.ToString(), ["Name"] = S(line["Name"]), ["VoltageClassCode"] = S(line["VoltageClassCode"]),
                                           ["NearStation"] = S(near?["StationName"]), ["RemoteStation"] = S(far?["StationName"]), ["Terminals"] = terms.Count };
                st.Facts["line.Name"] = S(line["Name"]);
                if (near is not null) st.Facts["line.NearStation"] = S(near["StationName"]);
                if (far is not null) st.Facts["line.RemoteStation"] = S(far["StationName"]);
                if (decimal.TryParse(kvText, NumberStyles.Any, CultureInfo.InvariantCulture, out var kv)) st.Facts["line.kV"] = new Quantity(kv);
                foreach (var c in await s.RowsAsync("SELECT CharacteristicKey, TextValue, IntegerValue, DecimalValue, BooleanValue FROM asset.vAssetCharacteristic WHERE AssetEntityId = @l AND ValidTo IS NULL", new Dictionary<string, object?> { ["@l"] = lineId }, ct))
                {
                    var o = (JsonObject)c!; var key = "line." + S(o["CharacteristicKey"]);
                    if (D(o["DecimalValue"]) is { } dv) st.Facts[key] = new Quantity(dv);
                    else if (D(o["IntegerValue"]) is { } iv) st.Facts[key] = new Quantity(iv);
                    else if (o["TextValue"] is not null) st.Facts[key] = S(o["TextValue"]);
                }
            }
        }
        foreach (var f in st.Template!["facts"] as JsonArray ?? new JsonArray())
        {
            var name = S(f?["name"]);
            if (!st.Facts.ContainsKey(name)) st.Missing.Add(name);
        }
        // the position's commissioned functions, for the elements' "in use" defaults (no rows: everything offered as in use)
        try
        {
            foreach (var r in await s.RowsAsync("""
                SELECT cf.AnsiCode FROM scheme.vCommissionedFunction cf JOIN location.vNode n ON n.EntityId = cf.ProtectionFunctionNodeEntityId
                WHERE n.ParentEntityId = @p
                """, new Dictionary<string, object?> { ["@p"] = G(rec["PositionNodeEntityId"]) ?? Guid.Empty }, ct))
                st.Commissioned.Add(S(r?["AnsiCode"]));
        }
        catch (Microsoft.Data.SqlClient.SqlException) { /* the view's shape is not this one on this environment: no defaults from it */ }
        return st;
    }

    static State Copy(State st, JsonObject? map) => new()
    {
        Record = st.Record, DefinitionEntityId = st.DefinitionEntityId, TemplateVersionRowId = st.TemplateVersionRowId, Template = st.Template, Map = map,
        Defs = st.Defs, RationaleRevisionRowId = st.RationaleRevisionRowId, RationaleStatus = st.RationaleStatus, Stored = st.Stored, Line = st.Line, LineSource = st.LineSource, Files = st.Files, LastResult = st.LastResult
    };

    /// <summary>The state as the page reads it: template (inputs by section with defaults), map, facts, missing, inputs (stored over defaults), last result, files.</summary>
    public static JsonObject Describe(State st)
    {
        var inputs = new JsonObject();
        foreach (var i in st.Template?["inputs"] as JsonArray ?? new JsonArray())
        {
            var key = S(i?["key"]);
            inputs[key] = st.Stored.TryGetValue(key, out var v) ? v : (i?["default"]?.ToString());
        }
        var facts = new JsonObject();
        foreach (var (k, v) in st.Facts) facts[k] = v is Quantity q ? JsonValue.Create(q.Value) : JsonValue.Create(v?.ToString());
        return new JsonObject
        {
            ["revisionRowId"] = S(st.Record["RevisionRowId"]), ["gridState"] = S(st.Record["GridState"]), ["revisionStatus"] = S(st.Record["RevisionStatus"]),
            ["device"] = new JsonObject { ["entityId"] = S(st.Record["DeviceEntityId"]), ["name"] = S(st.Record["DeviceName"]), ["station"] = S(st.Record["StationName"]), ["model"] = S(st.Record["ModelName"]) },
            ["template"] = st.Template is null ? null : new JsonObject { ["definitionEntityId"] = st.DefinitionEntityId.ToString(), ["versionRowId"] = st.TemplateVersionRowId.ToString(), ["key"] = S(st.Template["key"]), ["name"] = S(st.Template["name"]),
                                                                            ["inputs"] = st.Template["inputs"]?.DeepClone(), ["sections"] = SectionsForPage(st.Template), ["sources"] = st.Template["sources"]?.DeepClone() },
            ["map"] = st.Map is null ? null : new JsonObject { ["elements"] = st.Map["elements"]?.DeepClone(), ["groups"] = st.Map["groups"]?.DeepClone() },
            ["line"] = st.Line?.DeepClone(), ["lineSource"] = st.LineSource, ["facts"] = facts, ["missing"] = new JsonArray(st.Missing.Select(m => (JsonNode)JsonValue.Create(m)).ToArray()),
            ["commissioned"] = new JsonArray(st.Commissioned.Select(m => (JsonNode)JsonValue.Create(m)).ToArray()),
            ["rationale"] = st.RationaleRevisionRowId is null ? null : new JsonObject { ["revisionRowId"] = st.RationaleRevisionRowId.ToString(), ["status"] = st.RationaleStatus },
            ["inputs"] = inputs, ["files"] = st.Files.DeepClone(), ["lastResult"] = st.LastResult?.DeepClone(),
        };
    }

    static JsonArray SectionsForPage(JsonObject tpl)
    {
        var a = new JsonArray();
        foreach (var sec in tpl["sections"] as JsonArray ?? new JsonArray())
        {
            var o = (JsonObject)sec!;
            a.Add(new JsonObject { ["key"] = S(o["key"]), ["kind"] = S(o["kind"]), ["title"] = S(o["title"]), ["statement"] = S(o["statement"]),
                                   ["settings"] = new JsonArray((o["settings"] as JsonArray ?? new JsonArray()).Select(x => (JsonNode)new JsonObject { ["code"] = S(x?["code"]), ["exprText"] = S(x?["exprText"]) }).ToArray()) });
        }
        return a;
    }

    sealed class DictReader(Dictionary<string, object?> facts) : IFactReader
    {
        public object? Read(object? subject, string name, IReadOnlyDictionary<string, object> parameters, DateTimeOffset at) => facts.TryGetValue(name, out var v) ? v : null;
    }

    public static async Task<JsonObject> ApplyAsync(SqlSession s, State st, JsonObject posted, Guid actorId, string actorName, CancellationToken ct)
    {
        if (st.Template is null) throw new ApiException(404, "no_template", "This model has no rationale template.");
        if (S(st.Record["RevisionStatus"]) != "Draft") throw new ApiException(409, "not_outstanding", "A rationale is applied to an outstanding (Draft) revision only; this revision is issued and its rationale is frozen.");
        // #231: the settings are on the relay (the package's lifecycle state locks them, process.fSettingsLocked via the view) — refused before a rationale revision is made
        if (st.Record["SettingsLocked"] is JsonNode lockedNode && (lockedNode.ToString() is "true" or "True" or "1"))
            throw new ApiException(409, "settings_locked", "These settings have been loaded on the relay, so the rationale is no longer applied to them in this request. Finish the request, or raise a new change to alter them.");
        var settingsRevision = G(st.Record["RevisionRowId"])!.Value; var device = G(st.Record["DeviceEntityId"])!.Value;
        // #230: the settings file follows the settings, written once after the whole apply — and a file that cannot be written from
        // its settings (settings the template does not read) is refused here, before anything is written
        const string WriteFile = """
            SET NOCOUNT ON; DECLARE @fn NVARCHAR(255), @wr BIT;
            EXEC process.IssueRenderedSettings @ConfigurationFileRevisionRowId = @rev, @ActorId = @a, @Reparse = 0, @FileName = @fn OUTPUT, @Written = @wr OUTPUT;
            """;
        await s.ExecAsync(WriteFile, new Dictionary<string, object?> { ["@rev"] = settingsRevision, ["@a"] = actorId }, ct);
        // the inputs: defaults, then what stands, then what was posted
        var inputs = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase); var tables = new Dictionary<string, JsonNode?>(StringComparer.OrdinalIgnoreCase);
        var inputDefs = (st.Template["inputs"] as JsonArray ?? new JsonArray()).Select(i => (JsonObject)i!).ToList();
        foreach (var i in inputDefs) inputs[S(i["key"])] = i["default"]?.ToString();
        foreach (var (k, v) in st.Stored) inputs[k] = v;
        foreach (var (k, v) in posted)
        {
            if (v is JsonArray or JsonObject) tables[k] = v?.DeepClone(); else inputs[k] = v is null ? null : (v is JsonValue jv && jv.TryGetValue<bool>(out var b) ? (b ? "Y" : "N") : v.ToString());
        }
        if (st.Line is not null) inputs["Line"] = S(st.Line["EntityId"]);
        if (st.LastResult?["tables"] is JsonObject lastTables) foreach (var (k, v) in lastTables) if (!tables.ContainsKey(k)) tables[k] = v?.DeepClone();
        // the rationale revision
        var created = await s.RowsAsync("""
            SET NOCOUNT ON; DECLARE @rr UNIQUEIDENTIFIER, @doc UNIQUEIDENTIFIER, @c BIT;
            EXEC document.CreateRationale @ConfigurationFileRevisionRowId = @rev, @DefinitionVersionRowId = @v, @ActorId = @a, @RevisionRowId = @rr OUTPUT, @DocumentEntityId = @doc OUTPUT, @Created = @c OUTPUT;
            SELECT @rr AS RevisionRowId, @doc AS DocumentEntityId, @c AS Created
            """, new Dictionary<string, object?> { ["@rev"] = settingsRevision, ["@v"] = st.TemplateVersionRowId, ["@a"] = actorId }, ct);
        var rr = G(created.FirstOrDefault()?["RevisionRowId"]) ?? throw new ApiException(500, "rationale", "The rationale revision was not created.");
        st.RationaleRevisionRowId = rr;
        // the facts the formulas read
        var facts = new Dictionary<string, object?>(st.Facts, StringComparer.Ordinal);
        foreach (var i in inputDefs)
        {
            var key = S(i["key"]); var dt = S(i["dataType"]);
            if (!inputs.TryGetValue(key, out var raw) || string.IsNullOrWhiteSpace(raw)) continue;
            facts["input." + key] = dt switch
            {
                "Decimal" or "Integer" => decimal.TryParse(raw, NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? new Quantity(d) : null,
                "Boolean" => raw is "Y" or "y" or "true" or "True" or "1",
                _ => raw,
            };
        }
        var reader = new DictReader(facts); var now = await s.NowAsync(ct);   // the database's time, as everything it records (2026-09-23)
        var sections = new JsonArray(); var written = new List<(string code, string raw)>(); var unknowns = new List<string>();
        var elements = (st.Map?["elements"] as JsonArray ?? new JsonArray()).Select(e => (JsonObject)e!).ToDictionary(e => S(e["key"]), e => e, StringComparer.OrdinalIgnoreCase);
        foreach (var secNode in st.Template["sections"] as JsonArray ?? new JsonArray())
        {
            var sec = (JsonObject)secNode!; var key = S(sec["key"]); var kind = S(sec["kind"]);
            var used = !inputs.TryGetValue("Used_" + key, out var u) || u is null || u is "Y" or "y" or "true" or "1";
            var secOut = new JsonObject { ["key"] = key, ["kind"] = kind, ["title"] = S(sec["title"]), ["used"] = used };
            var values = new JsonObject(); var setOut = new JsonArray();
            foreach (var v in sec["values"] as JsonArray ?? new JsonArray())
            {
                var name = S(v?["name"]);
                var r = Evaluator.Evaluate((JsonObject)v!["expr"]!, reader, null, now);
                facts["value." + name] = Values.IsUnknown(r.Value) ? null : r.Value;
                values[name] = Values.IsUnknown(r.Value) ? null : Text(r.Value);
                if (Values.IsUnknown(r.Value)) unknowns.Add(key + "." + name + ": " + string.Join("; ", r.Unknowns));
            }
            if (used)
                foreach (var w in sec["settings"] as JsonArray ?? new JsonArray())
                {
                    var code = S(w?["code"]);
                    var r = Evaluator.Evaluate((JsonObject)w!["expr"]!, reader, null, now);
                    if (Values.IsUnknown(r.Value)) { unknowns.Add(key + " " + code + ": " + string.Join("; ", r.Unknowns)); setOut.Add(new JsonObject { ["code"] = code, ["value"] = null, ["unknown"] = string.Join("; ", r.Unknowns) }); continue; }
                    var raw = Text(r.Value);
                    facts["setting." + code] = r.Value; written.Add((code, raw));
                    setOut.Add(new JsonObject { ["code"] = code, ["value"] = raw });
                }
            secOut["values"] = values; secOut["settings"] = setOut;
            secOut["supervision"] = kind == "element" && elements.TryGetValue(key, out var el) ? Supervision(el, elements, facts) : "";
            secOut["statement"] = used ? Render(S(sec["statement"]), facts, inputs, S(secOut["supervision"]), inputs.TryGetValue("Note_" + key, out var note) ? note ?? "" : "") : "Not in use at this position.";
            sections.Add(secOut);
        }
        // the derived masks from the elements' marks, in the Relay Word's bit order
        var masks = new JsonObject();
        if (st.Map?["rows"] is JsonArray rows && st.Template["derivedMasks"] is JsonObject derived)
        {
            var order = rows.Select(r => (r as JsonArray ?? new JsonArray()).Select(b => S(b?["code"])).ToList()).ToList();
            foreach (var (mask, spec) in derived)
            {
                var bits = new HashSet<string>(StringComparer.OrdinalIgnoreCase); var marks = new List<string>();
                foreach (var (elKey, outs) in spec!["outputs"] as JsonObject ?? new JsonObject())
                {
                    var usedEl = !inputs.TryGetValue("Used_" + elKey, out var uu) || uu is null || uu is "Y" or "y" or "true" or "1";
                    var on = inputs.TryGetValue(S(spec["input"]) + "_" + elKey, out var m) && m is "Y" or "y" or "true" or "1";
                    if (usedEl && on) { foreach (var o in outs as JsonArray ?? new JsonArray()) bits.Add(S(o)); marks.Add(elKey); }
                }
                var hex = string.Join(" ", order.Select(row => { var b = 0; for (var i = 0; i < row.Count && i < 8; i++) if (bits.Contains(row[i])) b |= 0x80 >> i; return b.ToString("X2"); }));
                masks[mask] = new JsonObject { ["value"] = hex, ["bits"] = new JsonArray(bits.Select(b => (JsonNode)JsonValue.Create(b)).ToArray()), ["from"] = string.Join(", ", marks) };
                written.Add((mask, hex));
            }
        }
        // write the settings and the inputs
        var rangeNotes = new JsonObject();
        foreach (var (code, raw) in written)
        {
            var rc = await s.RowsAsync("""
                SET NOCOUNT ON; DECLARE @rc NVARCHAR(20), @rn NVARCHAR(400);
                EXEC process.SetParsedSetting @ConfigurationFileRevisionRowId = @rev, @DeviceEntityId = @d, @SettingCode = @c, @RawValue = @v, @DeferFileWrite = 1, @ActorId = @a, @RangeCheck = @rc OUTPUT, @RangeCheckNote = @rn OUTPUT;
                SELECT @rc AS RangeCheck, @rn AS Note
                """, new Dictionary<string, object?> { ["@rev"] = settingsRevision, ["@d"] = device, ["@c"] = code, ["@v"] = raw, ["@a"] = actorId }, ct);
            var r0 = rc.FirstOrDefault(); if (S(r0?["RangeCheck"]) == "OutOfRange") rangeNotes[code] = "OutOfRange" + (S(r0?["Note"]) == "" ? "" : ": " + S(r0?["Note"]));
        }
        if (written.Count > 0) await s.ExecAsync(WriteFile, new Dictionary<string, object?> { ["@rev"] = settingsRevision, ["@a"] = actorId }, ct);
        foreach (var i in inputDefs)
        {
            var key = S(i["key"]); if (S(i["dataType"]) == "Table" || !st.Defs.ContainsKey(key)) continue;
            await s.ExecAsync("EXEC document.SetRationaleValue @RevisionRowId = @rr, @CharacteristicKey = @k, @Value = @v, @ActorId = @a",
                new Dictionary<string, object?> { ["@rr"] = rr, ["@k"] = key, ["@v"] = inputs.TryGetValue(key, out var v) ? v : null, ["@a"] = actorId }, ct);
        }
        // the result and the document
        var result = new JsonObject
        {
            ["appliedAt"] = now, ["appliedBy"] = actorName, ["template"] = S(st.Template["key"]), ["templateVersionRowId"] = st.TemplateVersionRowId.ToString(),
            ["line"] = st.Line?.DeepClone(), ["lineSource"] = st.LineSource,
            ["facts"] = new JsonObject(st.Facts.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)JsonValue.Create(Text(kv.Value))))),
            ["inputs"] = new JsonObject(inputs.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)(kv.Value is null ? null : JsonValue.Create(kv.Value))))),
            ["tables"] = new JsonObject(tables.Select(kv => KeyValuePair.Create(kv.Key, kv.Value?.DeepClone()))),
            ["sections"] = sections, ["masks"] = masks,
            ["settingsWritten"] = new JsonArray(written.Select(w => (JsonNode)new JsonObject { ["code"] = w.code, ["value"] = w.raw }).ToArray()),
            ["rangeChecks"] = rangeNotes, ["unknown"] = new JsonArray(unknowns.Select(x => (JsonNode)JsonValue.Create(x)).ToArray()),
        };
        var history = await s.RowsAsync("""
            SELECT r.RevisionLabel, r.Status, r.ChangeNote, CONVERT(NVARCHAR(30), COALESCE(r.IssuedAt, r.ApprovedAt, r.PreparedAt, r.CreatedAt), 126) AS At, COALESCE(pp.DisplayName, p.SystemName) AS DisplayName
            FROM document.vRevision r LEFT JOIN personnel.vActor p ON p.ActorId = COALESCE(r.PreparedByActorId, r.CreatedBy) LEFT JOIN personnel.vPerson pp ON pp.EntityId = p.PersonEntityId
            WHERE r.DocumentEntityId = @doc ORDER BY r.CreatedAt
            """, new Dictionary<string, object?> { ["@doc"] = G(st.Record["DocumentEntityId"]) ?? Guid.Empty }, ct);
        var docx = BuildDocx(st, result, history);
        var json = Encoding.UTF8.GetBytes(result.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        // the previous pair is withdrawn (soft-deleted; the file store keeps the bytes, as every record is kept) and the new pair filed under
        // a stamped name — File_Write refuses a name the revision's store already holds (process.RefileRevision's precedent: a fresh name)
        foreach (var f in st.Files.Where(f => IsRationaleFile(S(f?["FileName"]), ".json") || IsRationaleFile(S(f?["FileName"]), ".docx")))
            await s.ExecAsync("EXEC document.File_SoftDelete @EntityId = @e, @ActorId = @a", new Dictionary<string, object?> { ["@e"] = G(f?["EntityId"]), ["@a"] = actorId }, ct);
        var stamp = now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        await s.ExecAsync("EXEC document.File_Write @RevisionRowId = @rr, @FileName = @n, @MimeType = N'application/json', @Content = @c, @FileRole = N'Attachment', @ActorId = @a",
            new Dictionary<string, object?> { ["@rr"] = rr, ["@n"] = $"rationale-{stamp}.json", ["@c"] = json, ["@a"] = actorId }, ct);
        await s.ExecAsync("EXEC document.File_Write @RevisionRowId = @rr, @FileName = @n, @MimeType = N'application/vnd.openxmlformats-officedocument.wordprocessingml.document', @Content = @c, @FileRole = N'Native', @ActorId = @a",
            new Dictionary<string, object?> { ["@rr"] = rr, ["@n"] = $"rationale-{stamp}.docx", ["@c"] = docx, ["@a"] = actorId }, ct);
        var detail = new JsonObject { ["action"] = "rationale-applied", ["configurationFileRevisionRowId"] = settingsRevision.ToString(), ["template"] = S(st.Template["key"]),
                                      ["settings"] = new JsonObject(written.Select(w => KeyValuePair.Create(w.code, (JsonNode?)JsonValue.Create(w.raw)))), ["line"] = st.Line?["Name"]?.DeepClone() };
        await s.ExecAsync("EXEC audit.LogAction @ActionKindCode = N'Administrative', @SubjectSchema = N'document', @SubjectTable = N'Revision', @SubjectRowId = @rr, @ActorId = @a, @Detail = @d",
            new Dictionary<string, object?> { ["@rr"] = rr, ["@a"] = actorId, ["@d"] = detail.ToJsonString() }, ct);
        result["rationaleRevisionRowId"] = rr.ToString();
        return result;
    }

    public static bool IsRationaleFile(string name, string ext) => name.StartsWith("rationale", StringComparison.OrdinalIgnoreCase) && name.EndsWith(ext, StringComparison.OrdinalIgnoreCase);

    static string Text(object? v) => v switch { null => "", Quantity q => Dec(q.Value), bool b => b ? "Y" : "N", Unknown => "", _ => v.ToString() ?? "" };

    /// <summary>The map's supervision line for an element, with the supervisors' values where they are settings already written.</summary>
    static string Supervision(JsonObject el, Dictionary<string, JsonObject> elements, Dictionary<string, object?> facts)
    {
        var parts = new List<string>();
        foreach (var sup in el["supervisedBy"] as JsonArray ?? new JsonArray())
        {
            var by = S(sup?["by"]); var vals = new List<string>();
            foreach (var code in by.Split('|'))
            {
                var owner = elements.Values.FirstOrDefault(e => (e["outputs"] as JsonArray ?? new JsonArray()).Any(o => S(o) == code));
                foreach (var sc in owner?["settings"] as JsonArray ?? new JsonArray())
                    if (facts.TryGetValue("setting." + S(sc), out var v) && v is not null) vals.Add(S(sc) + " = " + Text(v));
            }
            parts.Add(by.Replace("|", " or ") + (vals.Count > 0 ? " (" + string.Join(", ", vals) + ")" : "") + " — " + S(sup?["how"]) + " (" + S(sup?["cite"]) + ")");
        }
        return parts.Count == 0 ? "" : "Supervised by " + string.Join("; ", parts) + ".";
    }

    static string Render(string statement, Dictionary<string, object?> facts, Dictionary<string, string?> inputs, string supervision, string note)
    {
        var sb = new StringBuilder(); var i = 0;
        while (i < statement.Length)
        {
            var open = statement.IndexOf('{', i); if (open < 0) { sb.Append(statement, i, statement.Length - i); break; }
            var close = statement.IndexOf('}', open); if (close < 0) { sb.Append(statement, i, statement.Length - i); break; }
            sb.Append(statement, i, open - i);
            var name = statement.Substring(open + 1, close - open - 1);
            if (name == "supervision") sb.Append(supervision);
            else if (name == "note") sb.Append(note);
            else if (facts.TryGetValue(name, out var v) && v is not null) sb.Append(Text(v));
            else if (name.StartsWith("input.") && inputs.TryGetValue(name[6..], out var iv) && iv is not null) sb.Append(iv);
            else sb.Append('—');
            i = close + 1;
        }
        return sb.ToString().Replace("  ", " ").Trim();
    }

    static byte[] BuildDocx(State st, JsonObject result, JsonArray history)
    {
        var d = new DocxDocument();
        var rec = st.Record;
        d.Title(S(rec["StationName"])).Title(S(rec["SchemeName"]) is { Length: > 0 } sn ? sn : S(rec["DeviceName"]))
         .Subtitle(S(st.Template?["name"])).Subtitle("P&C Engineering").Subtitle("rationale.docx — generated by the platform " + result["appliedAt"]?.ToString()?[..10]);
        d.Heading("Revision History");
        d.Table(new[] { "Revision", "Status", "By", "Description", "Date" },
            history.Select(h => (IReadOnlyList<string>)new[] { S(h?["RevisionLabel"]), S(h?["Status"]), S(h?["DisplayName"]), S(h?["ChangeNote"]), S(h?["At"]) is { Length: >= 10 } at ? at[..10] : "" }));
        d.Paragraph("Relay: " + S(rec["ModelName"]) + " (" + S(rec["DeviceName"]) + ")");
        var elements = (st.Map?["elements"] as JsonArray ?? new JsonArray()).Select(e => (JsonObject)e!).ToDictionary(e => S(e["key"]), e => e, StringComparer.OrdinalIgnoreCase);
        foreach (var sec in result["sections"] as JsonArray ?? new JsonArray())
        {
            var o = (JsonObject)sec!; var kind = S(o["kind"]); var key = S(o["key"]);
            if (kind == "shared")
            {
                d.Heading(S(o["title"])).Paragraph(S(o["statement"]));
                if (key == "FAULTSTUDY" && result["tables"]?["FaultStudy"] is JsonArray fs && fs.Count > 0)
                    d.Table(new[] { "Location", "IFault max gen (A)", "IFault min gen (A)", "Comment" }, fs.Select(r => (IReadOnlyList<string>)(r as JsonArray ?? new JsonArray()).Select(c => S(c)).ToArray()));
                continue;
            }
            if (kind == "element")
            {
                var el = elements.GetValueOrDefault(key);
                var head = S(o["title"]) + (el is null ? "" : " — outputs " + string.Join(", ", (el["outputs"] as JsonArray ?? new JsonArray()).Select(x => S(x))) + "; owns " + string.Join(", ", (el["settings"] as JsonArray ?? new JsonArray()).Select(x => S(x))));
                d.Numbered(head + "\n" + S(o["statement"]));
                var vals = (o["settings"] as JsonArray ?? new JsonArray()).Where(x => x?["value"] is not null).Select(x => S(x?["code"]) + " = " + S(x?["value"])).ToList();
                if (vals.Count > 0) d.Mono(string.Join("    ", vals));
            }
            else d.Heading(S(o["title"])).Paragraph(S(o["statement"]));
        }
        d.Heading("Mask Settings");
        d.Table(new[] { "Mask", "Hex", "Bits", "From" }, (result["masks"] as JsonObject ?? new JsonObject()).Select(m => (IReadOnlyList<string>)new[] { m.Key, S(m.Value?["value"]), string.Join(" ", (m.Value?["bits"] as JsonArray ?? new JsonArray()).Select(b => S(b))), S(m.Value?["from"]) }));
        d.Heading("Settings Summary");
        d.Mono(string.Join("\n", (result["settingsWritten"] as JsonArray ?? new JsonArray()).Select(w => S(w?["code"]) + " = " + S(w?["value"]))));
        return d.ToBytes();
    }
}
