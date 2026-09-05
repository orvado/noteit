using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows.Threading;

namespace NoteIt;

/// <summary>
/// Central state: tabs, file IO, recents, autosave, find/replace engine,
/// snippets, export. Port of macOS DocumentStore.swift.
/// UI-agnostic (operates on plain strings); MainWindow syncs the RichTextBox.
/// </summary>
public sealed class DocumentStore : INotifyPropertyChanged
{
    public ObservableCollection<EditorDocument> Documents { get; } = new();
    public ObservableCollection<TextSnippet> Snippets { get; } = new();
    public ObservableCollection<string> RecentFiles { get; } = new();

    private Guid? _selectedId;
    public Guid? SelectedId
    {
        get => _selectedId;
        set { if (_selectedId != value) { _selectedId = value; OnPropertyChanged(); OnPropertyChanged(nameof(SelectedDocument)); } }
    }

    public EditorDocument? SelectedDocument
    {
        get
        {
            if (_selectedId is Guid id)
            {
                foreach (var d in Documents)
                    if (d.Id == id) return d;
            }
            return Documents.Count > 0 ? Documents[0] : null;
        }
    }

    public AppSettings Settings { get; } = new();
    public SearchOptions Search { get; } = new();

    private readonly DispatcherTimer _autosaveTimer;

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([System.Runtime.CompilerServices.CallerMemberName] string name = "")
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public DocumentStore()
    {
        LoadPersistedState();
        if (Documents.Count == 0) NewDocument();
        if (Snippets.Count == 0)
            foreach (var s in TextSnippet.Defaults()) Snippets.Add(s);

        Settings.PropertyChanged += (_, _) => { SaveSettings(); RestartAutosave(); };
        Snippets.CollectionChanged += (_, _) => SaveSnippets();
        RecentFiles.CollectionChanged += (_, _) => SaveRecents();

        _autosaveTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(Math.Max(2, Settings.AutoSaveInterval))
        };
        _autosaveTimer.Tick += (_, _) => AutosaveTick();
        _autosaveTimer.Start();
    }

    public void RestartAutosave()
    {
        _autosaveTimer.Interval = TimeSpan.FromSeconds(Math.Max(2, Settings.AutoSaveInterval));
        _autosaveTimer.Stop();
        if (Settings.AutoSaveEnabled) _autosaveTimer.Start();
        SaveSettings();
    }

    // MARK: - Tabs
    public EditorDocument NewDocument(string text = "", string? filePath = null)
    {
        var doc = new EditorDocument(text, filePath);
        Documents.Add(doc);
        SelectedId = doc.Id;
        return doc;
    }

    public void Select(EditorDocument doc) => SelectedId = doc.Id;

    /// <summary>Returns false when the user cancels the close.</summary>
    public bool CloseDocument(EditorDocument doc, Func<EditorDocument, bool>? savePrompt = null)
    {
        if (doc.IsDirty)
        {
            bool shouldSave;
            if (savePrompt != null)
            {
                // savePrompt returns true => save, false => don't save; throws CancelException to cancel.
                try { shouldSave = savePrompt(doc); }
                catch (OperationCanceledException) { return false; }
            }
            else
            {
                shouldSave = false;
            }
            if (shouldSave)
            {
                // Caller performs the actual save dialog; if still dirty, cancel.
                return false; // caller re-invokes after saving
            }
        }
        try
        {
            var draft = Path.Combine(AutosaveDir(), doc.Id + ".txt");
            if (File.Exists(draft)) File.Delete(draft);
        }
        catch { }
        Documents.Remove(doc);
        if (Documents.Count == 0) NewDocument();
        if (SelectedId == doc.Id) SelectedId = Documents[^1].Id;
        PruneStaleDrafts();
        return true;
    }

    public void RemoveDocument(EditorDocument doc)
    {
        try
        {
            var draft = Path.Combine(AutosaveDir(), doc.Id + ".txt");
            if (File.Exists(draft)) File.Delete(draft);
        }
        catch { }
        Documents.Remove(doc);
        if (Documents.Count == 0) NewDocument();
        if (SelectedId == doc.Id) SelectedId = Documents[^1].Id;
        PruneStaleDrafts();
    }

    // MARK: - File IO
    public bool OpenPath(string path)
    {
        try
        {
            string s = File.ReadAllText(path);
            foreach (var d in Documents)
            {
                if (string.Equals(d.FilePath, path, StringComparison.OrdinalIgnoreCase))
                {
                    d.SetClean(s, path);
                    SelectedId = d.Id;
                    PushRecent(path);
                    return true;
                }
            }
            // Reuse empty untitled tab
            if (Documents.Count == 1 && Documents[0].FilePath is null &&
                Documents[0].Text.Length == 0 && !Documents[0].IsDirty)
            {
                Documents[0].SetClean(s, path);
                SelectedId = Documents[0].Id;
            }
            else
            {
                var doc = NewDocument();
                doc.SetClean(s, path);
            }
            PushRecent(path);
            return true;
        }
        catch { return false; }
    }

    public bool SaveToPath(EditorDocument doc, string path)
    {
        try
        {
            File.WriteAllText(path, doc.Text);
            doc.SetClean(doc.Text, path);
            PushRecent(path);
            return true;
        }
        catch (Exception ex)
        {
            System.Windows.MessageBox.Show(ex.Message, "Save failed",
                System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Error);
            return false;
        }
    }

    public void Revert(EditorDocument doc)
    {
        if (doc.FilePath is null) return;
        try
        {
            string s = File.ReadAllText(doc.FilePath);
            doc.SetClean(s, doc.FilePath);
        }
        catch { }
    }

    // MARK: - Recents
    public void PushRecent(string path)
    {
        for (int i = RecentFiles.Count - 1; i >= 0; i--)
            if (string.Equals(RecentFiles[i], path, StringComparison.OrdinalIgnoreCase))
                RecentFiles.RemoveAt(i);
        RecentFiles.Insert(0, path);
        while (RecentFiles.Count > 15) RecentFiles.RemoveAt(RecentFiles.Count - 1);
    }

    public void ClearRecents() => RecentFiles.Clear();

    // MARK: - Autosave
    private static string AppDir()
    {
        string dir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "NoteIt");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public static string AutosaveDir()
    {
        string dir = Path.Combine(AppDir(), "Autosave");
        Directory.CreateDirectory(dir);
        return dir;
    }

    public void AutosaveTick()
    {
        if (!Settings.AutoSaveEnabled) return;
        foreach (var doc in Documents.ToArray())
        {
            if (!doc.IsDirty) continue;
            try
            {
                if (doc.FilePath is string fp)
                {
                    File.WriteAllText(fp, doc.Text);
                    doc.MarkClean();
                    var draft = Path.Combine(AutosaveDir(), doc.Id + ".txt");
                    if (File.Exists(draft)) File.Delete(draft);
                }
                else
                {
                    if (string.IsNullOrWhiteSpace(doc.Text)) continue;
                    File.WriteAllText(Path.Combine(AutosaveDir(), doc.Id + ".txt"), doc.Text);
                    // keep IsDirty true (still untitled) but draft is safe
                }
            }
            catch { }
        }
        PruneStaleDrafts();
    }

    public void PruneStaleDrafts()
    {
        try
        {
            string dir = AutosaveDir();
            var live = new HashSet<string>(Documents.Select(d => d.Id.ToString()));
            foreach (var f in Directory.GetFiles(dir, "*.txt"))
            {
                string baseName = Path.GetFileNameWithoutExtension(f);
                if (!live.Contains(baseName)) File.Delete(f);
            }
        }
        catch { }
    }

    // MARK: - Persistence
    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    private void LoadPersistedState()
    {
        try
        {
            string dir = AppDir();
            string settingsPath = Path.Combine(dir, "settings.json");
            if (File.Exists(settingsPath))
            {
                var s = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(settingsPath));
                if (s != null)
                {
                    Settings.FontName = s.FontName;
                    Settings.FontSize = s.FontSize;
                    Settings.WrapLines = s.WrapLines;
                    Settings.ShowLineNumbers = s.ShowLineNumbers;
                    Settings.Spellcheck = s.Spellcheck;
                    Settings.AutoSaveEnabled = s.AutoSaveEnabled;
                    Settings.AutoSaveInterval = s.AutoSaveInterval;
                    Settings.Appearance = s.Appearance;
                    Settings.TabWidth = s.TabWidth;
                }
            }
            string snippetsPath = Path.Combine(dir, "snippets.json");
            if (File.Exists(snippetsPath))
            {
                var list = JsonSerializer.Deserialize<List<TextSnippet>>(File.ReadAllText(snippetsPath));
                if (list != null) foreach (var s in list) Snippets.Add(s);
            }
            string recentsPath = Path.Combine(dir, "recents.json");
            if (File.Exists(recentsPath))
            {
                var list = JsonSerializer.Deserialize<List<string>>(File.ReadAllText(recentsPath));
                if (list != null) foreach (var p in list.Where(File.Exists).Take(15)) RecentFiles.Add(p);
            }
            // Restore autosaved drafts, oldest first, cap at 20
            string auto = AutosaveDir();
            var files = Directory.GetFiles(auto, "*.txt")
                .Select(f => new FileInfo(f))
                .OrderBy(f => f.LastWriteTimeUtc)
                .Take(20)
                .ToList();
            foreach (var f in files)
            {
                try
                {
                    string s = File.ReadAllText(f.FullName);
                    if (string.IsNullOrWhiteSpace(s)) { f.Delete(); continue; }
                    var doc = new EditorDocument();
                    Documents.Add(doc);
                    // Point the in-memory text at the draft without marking file-backed
                    doc.Text = s; // marks dirty
                    // Rename old draft file to the new doc's id so cleanup keeps working
                    string target = Path.Combine(auto, doc.Id + ".txt");
                    if (!string.Equals(f.FullName, target, StringComparison.OrdinalIgnoreCase))
                    {
                        if (File.Exists(target)) File.Delete(target);
                        f.MoveTo(target);
                    }
                }
                catch { try { f.Delete(); } catch { } }
            }
            // Delete anything beyond the cap (stale leaks)
            foreach (var f in Directory.GetFiles(auto, "*.txt").Skip(20))
            { try { File.Delete(f); } catch { } }
        }
        catch { }
    }

    private void SaveSettings()
    {
        try { File.WriteAllText(Path.Combine(AppDir(), "settings.json"), JsonSerializer.Serialize(Settings, JsonOpts)); }
        catch { }
    }

    private void SaveSnippets()
    {
        try { File.WriteAllText(Path.Combine(AppDir(), "snippets.json"), JsonSerializer.Serialize(Snippets.ToList(), JsonOpts)); }
        catch { }
    }

    private void SaveRecents()
    {
        try { File.WriteAllText(Path.Combine(AppDir(), "recents.json"), JsonSerializer.Serialize(RecentFiles.ToList(), JsonOpts)); }
        catch { }
    }

    // MARK: - Find / Replace engine (port of Swift ranges(of:))
    public List<(int Start, int Length)> RangesOf(string query, string text)
    {
        var out_ = new List<(int, int)>();
        if (string.IsNullOrEmpty(query)) return out_;
        if (Search.UseRegex)
        {
            try
            {
                var opts = RegexOptions.Compiled;
                if (!Search.CaseSensitive) opts |= RegexOptions.IgnoreCase;
                foreach (Match m in Regex.Matches(text, query, opts))
                    out_.Add((m.Index, m.Length));
            }
            catch { }
            return out_;
        }
        else
        {
            var cmp = Search.CaseSensitive ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;
            int from = 0;
            while (from <= text.Length)
            {
                int idx = text.IndexOf(query, from, cmp);
                if (idx < 0) break;
                if (Search.WholeWord && !IsWholeWord(text, idx, query.Length))
                {
                    from = idx + 1;
                    continue;
                }
                out_.Add((idx, query.Length));
                from = idx + Math.Max(1, query.Length);
                if (from > text.Length) break;
            }
            return out_;
        }
    }

    private static bool IsWholeWord(string text, int idx, int len)
    {
        bool beforeOk = idx == 0 || !char.IsLetterOrDigit(text[idx - 1]);
        bool afterOk = idx + len >= text.Length || !char.IsLetterOrDigit(text[idx + len]);
        return beforeOk && afterOk;
    }

    public int MatchCount(string query, string text) => RangesOf(query, text).Count;

    /// <summary>Find next match offset after caret; returns null when none (caller beeps).</summary>
    public (int Start, int Length)? FindNextMatch(string text, int caret)
    {
        var rs = RangesOf(Search.Query, text);
        if (rs.Count == 0) return null;
        foreach (var r in rs)
            if (r.Start > caret) return r;
        return Search.WrapAround ? rs[0] : null;
    }

    public (int Start, int Length)? FindPreviousMatch(string text, int caret)
    {
        var rs = RangesOf(Search.Query, text);
        if (rs.Count == 0) return null;
        for (int i = rs.Count - 1; i >= 0; i--)
            if (rs[i].Start < caret) return rs[i];
        return Search.WrapAround ? rs[^1] : null;
    }

    public bool SelectedTextMatches(string selected)
    {
        if (Search.UseRegex)
        {
            try
            {
                var opts = Search.CaseSensitive ? RegexOptions.None : RegexOptions.IgnoreCase;
                return Regex.IsMatch(selected, $"^(?:{Search.Query})$", opts);
            }
            catch { return false; }
        }
        return Search.CaseSensitive
            ? selected == Search.Query
            : string.Equals(selected, Search.Query, StringComparison.OrdinalIgnoreCase);
    }

    public string ReplaceAllIn(string original)
    {
        if (string.IsNullOrEmpty(Search.Query)) return original;
        if (Search.UseRegex)
        {
            try
            {
                var opts = Search.CaseSensitive ? RegexOptions.None : RegexOptions.IgnoreCase;
                // Literal replacement (Swift uses escapedTemplate)
                return Regex.Replace(original, Search.Query,
                    Search.Replacement.Replace("$", "$$"), opts);
            }
            catch { return original; }
        }
        var rs = RangesOf(Search.Query, original);
        if (rs.Count == 0) return original;
        var sb = new System.Text.StringBuilder(original);
        for (int i = rs.Count - 1; i >= 0; i--)
        {
            sb.Remove(rs[i].Start, rs[i].Length);
            sb.Insert(rs[i].Start, Search.Replacement);
        }
        return sb.ToString();
    }

    /// <summary>Character offset of the start of a 1-based line number, or null.</summary>
    public static int? OffsetOfLine(string text, int line)
    {
        int target = Math.Max(1, line);
        int loc = 0, count = 1;
        while (count < target)
        {
            int nl = text.IndexOf('\n', loc);
            if (nl < 0) return null;
            loc = nl + 1;
            count++;
        }
        return loc;
    }

    public static int LineLength(string text, int offset)
    {
        if (offset >= text.Length) return 0;
        int nl = text.IndexOf('\n', offset);
        return nl < 0 ? text.Length - offset : nl - offset;
    }

    // MARK: - Snippets
    public TextSnippet? FindSnippet(string trigger)
        => Snippets.FirstOrDefault(s => s.Trigger == trigger);

    /// <summary>
    /// Tab-triggered expansion: given full text + caret, returns (triggerStart, triggerLength, expansion)
    /// or null. Port of expandTriggerIfNeeded.
    /// </summary>
    public (int Start, int Length, string Expansion)? ExpandTrigger(string text, int caret)
    {
        if (caret <= 0 || caret > text.Length) return null;
        string prefix = text[..caret];
        int end = prefix.Length;
        int start = end;
        while (start > 0)
        {
            char c = prefix[start - 1];
            if (char.IsWhiteSpace(c) || "(){}[];,.\"'".Contains(c)) break;
            start--;
        }
        string word = prefix[start..];
        if (string.IsNullOrEmpty(word)) return null;
        var snip = FindSnippet(word);
        if (snip is null) return null;
        return (start, word.Length, snip.ResolvedExpansion());
    }

    // MARK: - Export / Print helpers
    public static void ExportPdf(EditorDocument doc, string path)
        => MiniPdfWriter.WriteTextFile(path, doc.Title, doc.Text);
}
