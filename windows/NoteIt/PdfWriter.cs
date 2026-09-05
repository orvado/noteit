using System.IO;
using System.Text;

namespace NoteIt;

/// <summary>
/// Zero-dependency minimal PDF 1.4 writer for Export-PDF parity.
/// Renders plain text in Courier 10pt with word-wrap + pagination (A4).
/// </summary>
public static class MiniPdfWriter
{
    public static void WriteTextFile(string path, string title, string text)
    {
        const float pageW = 595f, pageH = 842f; // A4 points
        const float margin = 56f;
        const float fontSize = 10f;
        const float leading = 13f;

        // Wrap: Courier is fixed-width -> ~600 char width units per char at 1000upm.
        float usable = pageW - margin * 2;
        float charW = fontSize * 0.6f;
        int maxChars = Math.Max(20, (int)(usable / charW));

        var pages = new List<List<string>>();
        var cur = new List<string>();
        int linesPerPage = (int)((pageH - margin * 2) / leading);

        void Flush() { if (cur.Count > 0) { pages.Add(new List<string>(cur)); cur.Clear(); } }

        foreach (string rawPara in (text ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            string para = rawPara;
            if (para.Length == 0) { cur.Add(""); if (cur.Count >= linesPerPage) Flush(); continue; }
            while (para.Length > 0)
            {
                string chunk = para.Length <= maxChars ? para : para[..maxChars];
                // Prefer breaking at space
                if (para.Length > maxChars)
                {
                    int sp = chunk.LastIndexOf(' ');
                    if (sp > maxChars / 2) chunk = chunk[..sp];
                }
                cur.Add(chunk);
                para = para.Length <= chunk.Length ? "" : para[chunk.Length..].TrimStart();
                if (cur.Count >= linesPerPage) Flush();
            }
        }
        Flush();
        if (pages.Count == 0) pages.Add(new List<string> { "" });

        static string Esc(string s) => s.Replace("\\", "\\\\").Replace("(", "\\(").Replace(")", "\\)");

        var objects = new List<string>();
        // 1: Catalog, 2: Pages, then page/page-content pairs, then font, then info
        int pageCount = pages.Count;
        var pageObjNums = new List<int>();
        var contentObjNums = new List<int>();
        int next = 3;
        for (int i = 0; i < pageCount; i++) { pageObjNums.Add(next++); contentObjNums.Add(next++); }
        int fontObj = next++;
        int infoObj = next++;

        var map = new Dictionary<int, string>
        {
            [1] = "<< /Type /Catalog /Pages 2 0 R >>",
            [2] = $"<< /Type /Pages /Kids [{string.Join(" ", pageObjNums.Select(n => $"{n} 0 R"))}] /Count {pageCount} >>",
            [fontObj] = "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
            [infoObj] = $"<< /Title ({Esc(title)}) /Producer (NoteIt for Windows) >>",
        };
        for (int i = 0; i < pageCount; i++)
        {
            map[pageObjNums[i]] =
                $"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {pageW} {pageH}] " +
                $"/Resources << /Font << /F1 {fontObj} 0 R >> >> /Contents {contentObjNums[i]} 0 R >>";
            var csb = new StringBuilder();
            csb.Append("BT /F1 ").Append(fontSize.ToString("0.##")).Append(" Tf ")
               .Append(margin.ToString("0.##")).Append(' ').Append((pageH - margin).ToString("0.##"))
               .Append(" Td ").Append(leading.ToString("0.##")).Append(" TL\n");
            foreach (string line in pages[i])
                csb.Append('(').Append(Esc(line)).Append(") Tj T*\n");
            csb.Append("ET");
            string stream = csb.ToString();
            map[contentObjNums[i]] = $"<< /Length {Encoding.ASCII.GetByteCount(stream)} >>\nstream\n{stream}\nendstream";
        }

        using var fs = new FileStream(path, FileMode.Create, FileAccess.Write);
        using var w = new StreamWriter(fs, Encoding.ASCII);
        // Build whole file with xref.
        var out_ = new StringBuilder();
        out_.Append("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n");
        var offs = new Dictionary<int, long>();
        foreach (int n in map.Keys.OrderBy(k => k))
        {
            offs[n] = out_.Length;
            out_.Append($"{n} 0 obj\n{map[n]}\nendobj\n");
        }
        long xrefPos = out_.Length;
        int maxObj = map.Keys.Max();
        out_.Append($"xref\n0 {maxObj + 1}\n");
        out_.Append("0000000000 65535 f \n");
        for (int i = 1; i <= maxObj; i++)
        {
            if (offs.TryGetValue(i, out long o)) out_.Append($"{o:0000000000} 00000 n \n");
            else out_.Append("0000000000 00000 f \n");
        }
        out_.Append($"trailer\n<< /Size {maxObj + 1} /Root 1 0 R /Info {infoObj} 0 R >>\nstartxref\n{xrefPos}\n%%EOF");
        w.Write(out_.ToString());
    }
}
