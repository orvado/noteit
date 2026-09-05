using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json.Serialization;

namespace NoteIt;

// MARK: - EditorDocument (port of macOS Models.swift)
public sealed class EditorDocument : INotifyPropertyChanged
{
    public Guid Id { get; } = Guid.NewGuid();

    private string _text = "";
    public string Text
    {
        get => _text;
        set
        {
            if (_text == value) return;
            _text = value;
            OnPropertyChanged();
            IsDirty = true;
            OnPropertyChanged(nameof(DisplayTitle));
            OnPropertyChanged(nameof(WordCount));
            OnPropertyChanged(nameof(LineCount));
        }
    }

    private string? _filePath;
    public string? FilePath
    {
        get => _filePath;
        set
        {
            if (_filePath == value) return;
            _filePath = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(Title));
            OnPropertyChanged(nameof(DisplayTitle));
        }
    }

    private bool _isDirty;
    public bool IsDirty
    {
        get => _isDirty;
        set
        {
            if (_isDirty == value) return;
            _isDirty = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(DisplayTitle));
        }
    }

    private int _cursorLine = 1;
    public int CursorLine { get => _cursorLine; set { if (_cursorLine != value) { _cursorLine = value; OnPropertyChanged(); } } }

    private int _cursorColumn = 1;
    public int CursorColumn { get => _cursorColumn; set { if (_cursorColumn != value) { _cursorColumn = value; OnPropertyChanged(); } } }

    private bool _formattingEnabled;
    /// <summary>When false the doc is plain-text only (no rich text / no formatting cmds).</summary>
    public bool FormattingEnabled { get => _formattingEnabled; set { if (_formattingEnabled != value) { _formattingEnabled = value; OnPropertyChanged(); } } }

    public EditorDocument() { }
    public EditorDocument(string text, string? filePath = null)
    {
        _text = text;
        _filePath = filePath;
        _isDirty = false;
    }

    public string Title => FilePath is null
        ? "Untitled"
        : System.IO.Path.GetFileNameWithoutExtension(FilePath);

    public string DisplayTitle => IsDirty ? $"{Title} •" : Title;

    public int WordCount
    {
        get
        {
            if (string.IsNullOrEmpty(_text)) return 0;
            int n = 0;
            bool inWord = false;
            foreach (char c in _text)
            {
                if (char.IsWhiteSpace(c)) inWord = false;
                else if (!inWord) { inWord = true; n++; }
            }
            return n;
        }
    }

    public int LineCount
    {
        get
        {
            if (_text.Length == 0) return 1;
            int n = 1;
            foreach (char c in _text) if (c == '\n') n++;
            return n;
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    internal void SetClean(string text, string? filePath)
    {
        _text = text;
        _filePath = filePath;
        _isDirty = false;
        OnPropertyChanged(nameof(Text));
        OnPropertyChanged(nameof(FilePath));
        OnPropertyChanged(nameof(IsDirty));
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(DisplayTitle));
        OnPropertyChanged(nameof(WordCount));
        OnPropertyChanged(nameof(LineCount));
    }

    internal void MarkClean()
    {
        _isDirty = false;
        OnPropertyChanged(nameof(IsDirty));
        OnPropertyChanged(nameof(DisplayTitle));
    }
}

// MARK: - TextSnippet
public sealed class TextSnippet
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Trigger { get; set; } = "";
    public string Expansion { get; set; } = "";
    public string Description { get; set; } = "";

    public TextSnippet() { }
    public TextSnippet(string trigger, string expansion, string description = "")
    {
        Trigger = trigger; Expansion = expansion; Description = description;
    }

    public static List<TextSnippet> Defaults() => new()
    {
        new("date", "{date}", "Today's date"),
        new("time", "{time}", "Current time"),
        new("lorem", "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", "Lorem ipsum"),
        new("sig", "— Sent from NoteIt", "Signature"),
        new("todo", "☐ TODO: ", "Todo item"),
        new("swiftlet", "let <#name#> = <#value#>", "Swift let"),
        new("swiftfunc", "func <#name#>(<#params#>) {\n    <#body#>\n}", "Swift func"),
    };

    public string ResolvedExpansion() => Expansion
        .Replace("{date}", DateTime.Now.ToString("d"))
        .Replace("{time}", DateTime.Now.ToString("t"));

    public override string ToString() => Trigger;
}

// MARK: - AppSettings
public sealed class AppSettings : INotifyPropertyChanged
{
    private string _fontName = "Cascadia Mono";
    public string FontName { get => _fontName; set { if (_fontName != value) { _fontName = value; OnPropertyChanged(); } } }

    private double _fontSize = 14.5;
    public double FontSize { get => _fontSize; set { if (_fontSize != value) { _fontSize = value; OnPropertyChanged(); } } }

    private bool _wrapLines = true;
    public bool WrapLines { get => _wrapLines; set { if (_wrapLines != value) { _wrapLines = value; OnPropertyChanged(); } } }

    private bool _showLineNumbers = true;
    public bool ShowLineNumbers { get => _showLineNumbers; set { if (_showLineNumbers != value) { _showLineNumbers = value; OnPropertyChanged(); } } }

    private bool _spellcheck = true;
    public bool Spellcheck { get => _spellcheck; set { if (_spellcheck != value) { _spellcheck = value; OnPropertyChanged(); } } }

    private bool _autoSaveEnabled = true;
    public bool AutoSaveEnabled { get => _autoSaveEnabled; set { if (_autoSaveEnabled != value) { _autoSaveEnabled = value; OnPropertyChanged(); } } }

    private double _autoSaveInterval = 5;
    public double AutoSaveInterval { get => _autoSaveInterval; set { if (_autoSaveInterval != value) { _autoSaveInterval = value; OnPropertyChanged(); } } }

    private AppearanceMode _appearance = AppearanceMode.System;
    public AppearanceMode Appearance { get => _appearance; set { if (_appearance != value) { _appearance = value; OnPropertyChanged(); } } }

    private int _tabWidth = 4;
    public int TabWidth { get => _tabWidth; set { if (_tabWidth != value) { _tabWidth = value; OnPropertyChanged(); } } }

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public enum AppearanceMode { System, Light, Dark }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

// MARK: - SearchOptions
public sealed class SearchOptions : INotifyPropertyChanged
{
    private string _query = "";
    public string Query { get => _query; set { if (_query != value) { _query = value; OnPropertyChanged(); } } }

    private string _replacement = "";
    public string Replacement { get => _replacement; set { if (_replacement != value) { _replacement = value; OnPropertyChanged(); } } }

    private bool _caseSensitive;
    public bool CaseSensitive { get => _caseSensitive; set { if (_caseSensitive != value) { _caseSensitive = value; OnPropertyChanged(); } } }

    private bool _wholeWord;
    public bool WholeWord { get => _wholeWord; set { if (_wholeWord != value) { _wholeWord = value; OnPropertyChanged(); } } }

    private bool _useRegex;
    public bool UseRegex { get => _useRegex; set { if (_useRegex != value) { _useRegex = value; OnPropertyChanged(); } } }

    private bool _wrapAround = true;
    public bool WrapAround { get => _wrapAround; set { if (_wrapAround != value) { _wrapAround = value; OnPropertyChanged(); } } }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
