using System.IO.Compression;
using System.Text;
using System.Xml;

namespace PnC.Api.Documents;

// #219 (2026-09-21): the settings-rationale generator writes a Word document, so the platform needs a writer for one.
// This is that writer, and nothing more: a .docx is a zip of XML parts, so it is built with System.IO.Compression and
// hand-escaped WordprocessingML — no NuGet package, no Office interop, no COM on the server. It covers exactly what a
// rationale needs (title block, revision-history table, headings, one running numbered list of decisions, paragraphs,
// small tables, monospace lines for settings text) and deliberately nothing else; anything richer belongs in a template.
// Output is deterministic (fixed entry order, fixed timestamps) so the same rationale twice is the same bytes.
public sealed class DocxDocument
{
    private const string W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    private const string R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private const int ContentTwips = 9360;                      // Letter (12240) less two 1-inch margins
    private static readonly DateTimeOffset Epoch = new(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private readonly StringBuilder _body = new();

    public DocxDocument Title(string text) => Para("<w:pStyle w:val=\"Title\"/>", null, text);

    public DocxDocument Subtitle(string text) => Para("<w:jc w:val=\"center\"/>", null, text);

    public DocxDocument Heading(string text) => Para("<w:pStyle w:val=\"Heading1\"/>", null, text);

    public DocxDocument Paragraph(string text) => Para("", null, text);

    // one running list for the whole document: every item shares numId 1, so Word continues 1., 2., 3. across headings
    public DocxDocument Numbered(string text) =>
        Para("<w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr>", null, text);

    public DocxDocument Bullet(string text) =>
        Para("<w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"2\"/></w:numPr>", null, text);

    public DocxDocument Mono(string text) => Para("<w:pStyle w:val=\"Mono\"/>", null, text);

    public DocxDocument Table(IReadOnlyList<string> header, IEnumerable<IReadOnlyList<string>> rows)
    {
        ArgumentNullException.ThrowIfNull(header);
        ArgumentNullException.ThrowIfNull(rows);
        var cols = header.Count;
        if (cols == 0) return this;
        var width = ContentTwips / cols;
        var last = ContentTwips - (width * (cols - 1));

        _body.Append("<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>");
        foreach (var side in new[] { "top", "left", "bottom", "right", "insideH", "insideV" })
            _body.Append($"<w:{side} w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/>");
        _body.Append("</w:tblBorders><w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"1\"")
             .Append(" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid>");
        for (var c = 0; c < cols; c++) _body.Append($"<w:gridCol w:w=\"{(c == cols - 1 ? last : width)}\"/>");
        _body.Append("</w:tblGrid>");

        Row(header, cols, width, last, isHeader: true);
        foreach (var row in rows) Row(row, cols, width, last, isHeader: false);
        _body.Append("</w:tbl>");
        Paragraph("");                                          // Word wants a paragraph after a table
        return this;
    }

    private void Row(IReadOnlyList<string> cells, int cols, int width, int last, bool isHeader)
    {
        _body.Append("<w:tr>");
        if (isHeader) _body.Append("<w:trPr><w:tblHeader/></w:trPr>");
        for (var c = 0; c < cols; c++)
        {
            var text = c < cells.Count ? cells[c] ?? "" : "";
            _body.Append($"<w:tc><w:tcPr><w:tcW w:w=\"{(c == cols - 1 ? last : width)}\" w:type=\"dxa\"/>");
            if (isHeader) _body.Append("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"D9D9D9\"/>");
            _body.Append("</w:tcPr><w:p><w:pPr><w:spacing w:after=\"40\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr>")
                 .Append(Runs(text, isHeader ? "<w:rPr><w:b/></w:rPr>" : null))
                 .Append("</w:p></w:tc>");
        }
        _body.Append("</w:tr>");
    }

    private DocxDocument Para(string pPrInner, string? rPr, string text)
    {
        _body.Append("<w:p>");
        if (pPrInner.Length > 0) _body.Append("<w:pPr>").Append(pPrInner).Append("</w:pPr>");
        _body.Append(Runs(text, rPr)).Append("</w:p>");
        return this;
    }

    // one run per line; a run after the first opens with w:br, which is the line break inside the paragraph
    private static string Runs(string? text, string? rPr)
    {
        var sb = new StringBuilder();
        var lines = (text ?? "").Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            sb.Append("<w:r>");
            if (rPr is not null) sb.Append(rPr);
            if (i > 0) sb.Append("<w:br/>");
            sb.Append("<w:t xml:space=\"preserve\">").Append(Esc(lines[i])).Append("</w:t></w:r>");
        }
        return sb.ToString();
    }

    private static string Esc(string s)
    {
        var sb = new StringBuilder(s.Length + 8);
        foreach (var ch in s)
        {
            if (ch == '&') sb.Append("&amp;");
            else if (ch == '<') sb.Append("&lt;");
            else if (ch == '>') sb.Append("&gt;");
            else if (ch == '"') sb.Append("&quot;");
            else if (ch == '\t' || ch >= ' ' || ch == '\n') sb.Append(ch);   // drop control characters XML forbids
        }
        return sb.ToString();
    }

    public byte[] ToBytes()
    {
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            Write(zip, "[Content_Types].xml", ContentTypes);
            Write(zip, "_rels/.rels", RootRels);
            Write(zip, "docProps/core.xml", CoreProps);
            Write(zip, "docProps/app.xml", AppProps);
            Write(zip, "word/_rels/document.xml.rels", DocRels);
            Write(zip, "word/document.xml", Document());
            Write(zip, "word/styles.xml", Styles);
            Write(zip, "word/numbering.xml", Numbering);
        }
        return ms.ToArray();
    }

    private static void Write(ZipArchive zip, string path, string xml)
    {
        var entry = zip.CreateEntry(path, CompressionLevel.Optimal);
        entry.LastWriteTime = Epoch;                             // deterministic: same document, same bytes
        using var s = entry.Open();
        var bytes = new UTF8Encoding(false).GetBytes(xml);
        s.Write(bytes, 0, bytes.Length);
    }

    private const string Decl = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n";

    private string Document() =>
        Decl + $"<w:document xmlns:w=\"{W}\" xmlns:r=\"{R}\"><w:body>" + _body +
        "<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/>" +
        "<w:pgMar w:top=\"1440\" w:right=\"1440\" w:bottom=\"1440\" w:left=\"1440\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>" +
        "<w:cols w:space=\"720\"/><w:docGrid w:linePitch=\"360\"/></w:sectPr></w:body></w:document>";

    private const string ContentTypes = Decl +
        "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
        "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
        "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
        "<Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>" +
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>" +
        "<Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>" +
        "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>" +
        "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>" +
        "</Types>";

    private const string RootRels = Decl +
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
        "<Relationship Id=\"rId1\" Type=\"" + R + "/officeDocument\" Target=\"word/document.xml\"/>" +
        "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/>" +
        "<Relationship Id=\"rId3\" Type=\"" + R + "/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>";

    private const string DocRels = Decl +
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
        "<Relationship Id=\"rId1\" Type=\"" + R + "/styles\" Target=\"styles.xml\"/>" +
        "<Relationship Id=\"rId2\" Type=\"" + R + "/numbering\" Target=\"numbering.xml\"/></Relationships>";

    // fixed properties: the generator's own metadata goes in the document body, not here, so the bytes stay deterministic
    private const string CoreProps = Decl +
        "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\"" +
        " xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\"" +
        " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">" +
        "<dc:creator>NB Power Engineering Platform</dc:creator><cp:lastModifiedBy>NB Power Engineering Platform</cp:lastModifiedBy>" +
        "<dcterms:created xsi:type=\"dcterms:W3CDTF\">1980-01-01T00:00:00Z</dcterms:created>" +
        "<dcterms:modified xsi:type=\"dcterms:W3CDTF\">1980-01-01T00:00:00Z</dcterms:modified></cp:coreProperties>";

    private const string AppProps = Decl +
        "<Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\"" +
        " xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\">" +
        "<Application>PnC.Api.Documents.DocxDocument</Application></Properties>";

    private const string Styles = Decl + "<w:styles xmlns:w=\"" + W + "\">" +
        "<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\" w:eastAsia=\"Calibri\" w:cs=\"Calibri\"/>" +
        "<w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr></w:rPrDefault>" +
        "<w:pPrDefault><w:pPr><w:spacing w:after=\"120\" w:line=\"259\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>" +
        "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>" +
        "<w:style w:type=\"character\" w:default=\"1\" w:styleId=\"DefaultParagraphFont\"><w:name w:val=\"Default Paragraph Font\"/><w:uiPriority w:val=\"1\"/><w:semiHidden/><w:unhideWhenUsed/></w:style>" +
        "<w:style w:type=\"numbering\" w:default=\"1\" w:styleId=\"NoList\"><w:name w:val=\"No List\"/><w:uiPriority w:val=\"99\"/><w:semiHidden/><w:unhideWhenUsed/></w:style>" +
        "<w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>" +
        "<w:pPr><w:spacing w:before=\"0\" w:after=\"120\" w:line=\"240\" w:lineRule=\"auto\"/><w:contextualSpacing/><w:jc w:val=\"center\"/></w:pPr>" +
        "<w:rPr><w:b/><w:sz w:val=\"56\"/><w:szCs w:val=\"56\"/></w:rPr></w:style>" +
        "<w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"Normal\"/><w:qFormat/>" +
        "<w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=\"280\" w:after=\"120\"/><w:outlineLvl w:val=\"0\"/></w:pPr>" +
        "<w:rPr><w:b/><w:color w:val=\"1F3864\"/><w:sz w:val=\"32\"/><w:szCs w:val=\"32\"/></w:rPr></w:style>" +
        "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/>" +
        "<w:pPr><w:spacing w:after=\"60\"/><w:ind w:left=\"720\"/><w:contextualSpacing/></w:pPr></w:style>" +
        "<w:style w:type=\"paragraph\" w:styleId=\"Mono\"><w:name w:val=\"Mono\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/>" +
        "<w:pPr><w:spacing w:after=\"60\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr>" +
        "<w:rPr><w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/><w:sz w:val=\"18\"/><w:szCs w:val=\"18\"/></w:rPr></w:style>" +
        "<w:style w:type=\"table\" w:default=\"1\" w:styleId=\"TableNormal\"><w:name w:val=\"Normal Table\"/><w:semiHidden/><w:unhideWhenUsed/>" +
        "<w:tblPr><w:tblInd w:w=\"0\" w:type=\"dxa\"/><w:tblCellMar><w:top w:w=\"0\" w:type=\"dxa\"/><w:left w:w=\"108\" w:type=\"dxa\"/>" +
        "<w:bottom w:w=\"0\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr></w:style>" +
        "<w:style w:type=\"table\" w:styleId=\"TableGrid\"><w:name w:val=\"Table Grid\"/><w:basedOn w:val=\"TableNormal\"/><w:uiPriority w:val=\"39\"/>" +
        "<w:tblPr><w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/><w:left w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/>" +
        "<w:bottom w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/><w:right w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/>" +
        "<w:insideH w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/><w:insideV w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"808080\"/>" +
        "</w:tblBorders></w:tblPr></w:style></w:styles>";

    private const string Numbering = Decl + "<w:numbering xmlns:w=\"" + W + "\">" +
        "<w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\">" +
        "<w:start w:val=\"1\"/><w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/><w:lvlJc w:val=\"left\"/>" +
        "<w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr></w:lvl></w:abstractNum>" +
        "<w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\">" +
        "<w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"\"/><w:lvlJc w:val=\"left\"/>" +
        "<w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr>" +
        "<w:rPr><w:rFonts w:ascii=\"Symbol\" w:hAnsi=\"Symbol\" w:hint=\"default\"/></w:rPr></w:lvl></w:abstractNum>" +
        "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num>" +
        "<w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num></w:numbering>";

    // every w:t of word/document.xml, joined with spaces — what the tests assert against
    public static string ExtractText(byte[] docx)
    {
        ArgumentNullException.ThrowIfNull(docx);
        using var ms = new MemoryStream(docx, writable: false);
        using var zip = new ZipArchive(ms, ZipArchiveMode.Read);
        var entry = zip.GetEntry("word/document.xml") ?? throw new InvalidDataException("word/document.xml is missing");
        using var s = entry.Open();
        using var reader = XmlReader.Create(s, new XmlReaderSettings { IgnoreWhitespace = false });
        var parts = new List<string>();
        while (reader.Read())
            if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "t" && reader.NamespaceURI == W)
                parts.Add(reader.ReadElementContentAsString());
        return string.Join(" ", parts);
    }
}
