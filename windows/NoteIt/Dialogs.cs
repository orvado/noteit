using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;

namespace NoteIt;

/// <summary>Go to Line dialog (parity with macOS GoToLineSheet, Ctrl+L).</summary>
public sealed class GoToLineWindow : Window
{
    public int? LineNumber { get; private set; }
    private readonly TextBox _box;

    public GoToLineWindow()
    {
        Title = "Go to Line";
        Width = 280;
        Height = 190;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var doc = App.Store.SelectedDocument;
        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = "Go to Line", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 4) });
        panel.Children.Add(new TextBlock
        {
            Text = doc != null ? $"1 … {doc.LineCount}" : "",
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 0, 0, 8)
        });
        _box = new TextBox { Width = 180, Text = doc != null ? doc.CursorLine.ToString() : "" };
        _box.KeyDown += (_, e) => { if (e.Key == Key.Enter) { Go(); } };
        panel.Children.Add(_box);
        var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 0) };
        var cancel = new Button { Content = "Cancel", Width = 75, Margin = new Thickness(0, 0, 8, 0), IsCancel = true };
        var go = new Button { Content = "Go", Width = 75, IsDefault = true };
        go.Click += (_, _) => Go();
        row.Children.Add(cancel); row.Children.Add(go);
        panel.Children.Add(row);
        Content = panel;
        Loaded += (_, _) => { _box.Focus(); _box.SelectAll(); };
    }

    private void Go()
    {
        if (int.TryParse(_box.Text.Trim(), out int n)) LineNumber = n;
        DialogResult = true;
    }
}

/// <summary>Quick open over recents (parity with macOS QuickOpenSheet, Ctrl+P).</summary>
public sealed class QuickOpenWindow : Window
{
    public string? ChosenPath { get; private set; }
    private readonly DocumentStore _store;
    private readonly TextBox _filter;
    private readonly ListBox _list;

    public QuickOpenWindow(DocumentStore store)
    {
        _store = store;
        Title = "Quick Open";
        Width = 540;
        Height = 360;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var panel = new DockPanel { Margin = new Thickness(16) };
        _filter = new TextBox { Margin = new Thickness(0, 0, 0, 8) };
        _filter.SetValue(TextBox.ToolTipProperty, "Type to filter recents, Enter to open, Browse for files");
        _filter.TextChanged += (_, _) => Refresh();
        _filter.KeyDown += (_, e) => { if (e.Key == Key.Enter) OpenFirst(); };
        DockPanel.SetDock(_filter, Dock.Top);
        panel.Children.Add(_filter);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        var browse = new Button { Content = "Browse…" };
        browse.Click += (_, _) =>
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = false };
            if (dlg.ShowDialog() == true) { ChosenPath = dlg.FileName; DialogResult = true; }
        };
        var spacer = new FrameworkElement { Width = 10 };
        var cancel = new Button { Content = "Cancel", IsCancel = true };
        var open = new Button { Content = "Open", IsDefault = true, Margin = new Thickness(8, 0, 0, 0) };
        open.Click += (_, _) => OpenSelected();
        var right = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(browse);
        buttons.Children.Add(new FrameworkElement { Width = 200 });
        buttons.Children.Add(cancel); buttons.Children.Add(open);
        DockPanel.SetDock(buttons, Dock.Bottom);
        panel.Children.Add(buttons);

        _list = new ListBox();
        _list.MouseDoubleClick += (_, _) => OpenSelected();
        _list.KeyDown += (_, e) => { if (e.Key == Key.Enter) OpenSelected(); };
        panel.Children.Add(_list);

        Content = panel;
        Refresh();
        Loaded += (_, _) => _filter.Focus();
    }

    private List<string> Candidates()
    {
        string q = _filter.Text.ToLowerInvariant();
        var base_ = _store.RecentFiles.ToList();
        if (string.IsNullOrWhiteSpace(q)) return base_.Take(10).ToList();
        return base_.Where(p => System.IO.Path.GetFileName(p).ToLowerInvariant().Contains(q)).ToList();
    }

    private void Refresh()
    {
        _list.Items.Clear();
        foreach (string p in Candidates())
            _list.Items.Add($"{System.IO.Path.GetFileName(p)}   —   {System.IO.Path.GetDirectoryName(p)}");
        if (_list.Items.Count > 0) _list.SelectedIndex = 0;
    }

    private void OpenFirst()
    {
        var c = Candidates();
        if (c.Count > 0) { ChosenPath = c[0]; DialogResult = true; }
    }

    private void OpenSelected()
    {
        var c = Candidates();
        int i = _list.SelectedIndex;
        if (i >= 0 && i < c.Count) { ChosenPath = c[i]; DialogResult = true; }
        else OpenFirst();
    }
}

/// <summary>Snippets manager + picker (parity with macOS SnippetsSheet, Ctrl+J).
/// Two panes: filterable snippet list on the left; live editor (trigger,
/// description, expansion) with validation and a resolved preview on the right.</summary>
public sealed class SnippetsWindow : Window
{
    private readonly DocumentStore _store;
    private readonly Action<TextSnippet> _onInsert;

    private readonly ListBox _list = new();
    private readonly TextBox _filter = new();
    private readonly TextBlock _count = new();
    private readonly ContentControl _detail = new();
    private readonly TextBox _triggerBox = new();
    private readonly TextBox _descriptionBox = new();
    private readonly TextBox _expansionBox = new();
    private readonly TextBlock _validation = new();
    private readonly TextBox _preview = new();
    private readonly Button _deleteButton = new() { Content = "Delete", Width = 60, Margin = new Thickness(4, 0, 0, 0) };
    private readonly Button _duplicateButton = new() { Content = "Duplicate", Width = 78, Margin = new Thickness(4, 0, 0, 0) };
    private readonly Button _insertButton = new() { Content = "Insert", Width = 75, Margin = new Thickness(0, 0, 8, 0) };
    private readonly FrameworkElement _editorPane;
    private readonly FrameworkElement _emptyPane;

    private List<TextSnippet> _filtered = new();
    private Guid? _selectedId;
    private bool _loading;    // loading a snippet into the editor, ignore TextChanged
    private bool _rebuilding; // rebuilding the list, ignore SelectionChanged

    public SnippetsWindow(DocumentStore store, Action<TextSnippet> onInsert)
    {
        _store = store;
        _onInsert = onInsert;
        Title = "Text Snippets";
        Width = 720;
        Height = 520;
        MinWidth = 560;
        MinHeight = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        // Windows "dark apps" mode resolves WPF's default system text brush to
        // white while this dialog stays light, rendering text invisible. Pin
        // explicit light colors; TextBoxes need their own (their theme style
        // overrides inherited values).
        Foreground = System.Windows.Media.Brushes.Black;
        Background = System.Windows.Media.Brushes.White;
        foreach (var box in new[] { _filter, _triggerBox, _descriptionBox, _expansionBox, _preview })
        {
            box.Foreground = System.Windows.Media.Brushes.Black;
            box.Background = System.Windows.Media.Brushes.White;
        }
        _preview.Background = System.Windows.Media.Brushes.WhiteSmoke;

        var root = new DockPanel();

        var header = new StackPanel { Margin = new Thickness(0, 14, 0, 10) };
        header.Children.Add(new TextBlock
        {
            Text = "Text Snippets", FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center
        });
        header.Children.Add(new TextBlock
        {
            Text = "Type a trigger then press Tab to expand. {date} and {time} auto-fill.",
            Foreground = System.Windows.Media.Brushes.Gray, FontSize = 11,
            HorizontalAlignment = HorizontalAlignment.Center
        });
        DockPanel.SetDock(header, Dock.Top);
        root.Children.Add(header);

        var footer = new DockPanel { Margin = new Thickness(12) };
        var restore = new Button { Content = "Restore Defaults", Width = 110 };
        restore.Click += (_, _) => RestoreDefaults();
        DockPanel.SetDock(restore, Dock.Left);
        footer.Children.Add(restore);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        _insertButton.Click += (_, _) => InsertSelected();
        var done = new Button { Content = "Done", Width = 75, IsDefault = true };
        done.Click += (_, _) => DialogResult = true;
        actions.Children.Add(_insertButton);
        actions.Children.Add(done);
        footer.Children.Add(actions);
        DockPanel.SetDock(footer, Dock.Bottom);
        root.Children.Add(footer);

        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(252) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var listPane = BuildListPane();
        Grid.SetColumn(listPane, 0);
        body.Children.Add(listPane);
        Grid.SetColumn(_detail, 1);
        body.Children.Add(_detail);
        root.Children.Add(body);

        _editorPane = BuildEditorPane();
        _emptyPane = BuildEmptyPane();
        _detail.Content = _emptyPane;

        _triggerBox.TextChanged += (_, _) => EditField(s => s.Trigger = _triggerBox.Text);
        _descriptionBox.TextChanged += (_, _) => EditField(s => s.Description = _descriptionBox.Text);
        _expansionBox.TextChanged += (_, _) => EditField(s => s.Expansion = _expansionBox.Text);
        foreach (var box in new[] { _triggerBox, _descriptionBox, _expansionBox })
        {
            box.LostFocus += (_, _) =>
            {
                _store.SaveSnippets();
                RefreshList(); // re-label the row (warning flag, subtitle) without disturbing the editor
            };
        }

        Content = root;
        RefreshList();
        Loaded += (_, _) =>
        {
            if (_selectedId is null && _store.Snippets.Count > 0) Select(_store.Snippets[0].Id);
            _triggerBox.Focus();
            _triggerBox.SelectAll();
        };
    }

    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        _store.SaveSnippets(); // persist any edit that never lost focus
        base.OnClosing(e);
    }

    // MARK: Layout

    private FrameworkElement BuildListPane()
    {
        var pane = new DockPanel();

        var bar = new DockPanel { Margin = new Thickness(8, 6, 8, 6) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var add = new Button { Content = "Add", Width = 48 };
        add.Click += (_, _) => AddSnippet();
        _deleteButton.Click += (_, _) => ConfirmDeleteSelected();
        _duplicateButton.Click += (_, _) => DuplicateSelected();
        buttons.Children.Add(add);
        buttons.Children.Add(_deleteButton);
        buttons.Children.Add(_duplicateButton);
        DockPanel.SetDock(buttons, Dock.Left);
        bar.Children.Add(buttons);
        _count.Foreground = System.Windows.Media.Brushes.Gray;
        _count.FontSize = 11;
        _count.VerticalAlignment = VerticalAlignment.Center;
        bar.Children.Add(_count);
        DockPanel.SetDock(bar, Dock.Top);
        pane.Children.Add(bar);

        _filter.Margin = new Thickness(8, 0, 8, 6);
        _filter.SetValue(TextBox.ToolTipProperty, "Filter by trigger, description, or expansion");
        _filter.TextChanged += (_, _) => RefreshList();
        DockPanel.SetDock(_filter, Dock.Top);
        pane.Children.Add(_filter);

        _list.Margin = new Thickness(8, 0, 0, 0);
        _list.BorderBrush = System.Windows.Media.Brushes.LightGray;
        _list.BorderThickness = new Thickness(0, 0, 0, 1);
        _list.MouseDoubleClick += (_, _) => InsertSelected();
        _list.KeyDown += (_, e) => { if (e.Key == Key.Delete) { ConfirmDeleteSelected(); e.Handled = true; } };
        _list.SelectionChanged += OnListSelectionChanged;
        pane.Children.Add(_list);
        return pane;
    }

    private FrameworkElement BuildEditorPane()
    {
        Mono(_triggerBox);
        _triggerBox.ToolTip = "The word you type before pressing Tab";
        _descriptionBox.ToolTip = "Optional note shown in the list";
        Mono(_expansionBox);
        _expansionBox.AcceptsReturn = true;
        _expansionBox.TextWrapping = TextWrapping.Wrap;
        _expansionBox.MinHeight = 140;
        _expansionBox.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        _validation.Foreground = System.Windows.Media.Brushes.DarkOrange;
        _validation.FontSize = 11;
        _validation.TextWrapping = TextWrapping.Wrap;
        _validation.Visibility = Visibility.Collapsed;
        Mono(_preview);
        _preview.IsReadOnly = true;
        _preview.TextWrapping = TextWrapping.Wrap;
        _preview.Background = System.Windows.Media.Brushes.WhiteSmoke;
        _preview.MinHeight = 56;
        _preview.MaxHeight = 80;
        _preview.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;

        var pane = new StackPanel { Margin = new Thickness(14, 10, 14, 0) };
        pane.Children.Add(Caption("Trigger"));
        pane.Children.Add(_triggerBox);
        pane.Children.Add(Caption("Description"));
        pane.Children.Add(_descriptionBox);
        pane.Children.Add(Caption("Expansion"));
        pane.Children.Add(_expansionBox);
        pane.Children.Add(_validation);
        pane.Children.Add(Caption("Preview — {date} / {time} resolved"));
        pane.Children.Add(_preview);
        return pane;
    }

    private static FrameworkElement BuildEmptyPane()
    {
        var pane = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        pane.Children.Add(new TextBlock
        {
            Text = "No snippet selected",
            Foreground = System.Windows.Media.Brushes.Gray, FontSize = 14
        });
        pane.Children.Add(new TextBlock
        {
            Text = "Pick one on the left, or click Add to create a new one.",
            Foreground = System.Windows.Media.Brushes.Gray, FontSize = 11,
            Margin = new Thickness(0, 6, 0, 0)
        });
        return pane;
    }

    private static TextBlock Caption(string text) => new()
    {
        Text = text,
        Foreground = System.Windows.Media.Brushes.Gray,
        FontSize = 11,
        Margin = new Thickness(0, 8, 0, 2)
    };

    private static void Mono(TextBox box) => box.FontFamily = new FontFamily("Cascadia Mono, Consolas");

    // MARK: List

    private void OnListSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_rebuilding) return;
        int i = _list.SelectedIndex;
        _selectedId = i >= 0 && i < _filtered.Count ? _filtered[i].Id : null;
        LoadDetail();
    }

    private void RefreshList()
    {
        string q = _filter.Text.Trim().ToLowerInvariant();
        _filtered = string.IsNullOrEmpty(q)
            ? _store.Snippets.ToList()
            : _store.Snippets.Where(s =>
                s.Trigger.ToLowerInvariant().Contains(q) ||
                s.Description.ToLowerInvariant().Contains(q) ||
                s.Expansion.ToLowerInvariant().Contains(q)).ToList();

        _rebuilding = true;
        _list.Items.Clear();
        foreach (var s in _filtered)
        {
            var row = new StackPanel();
            row.Children.Add(new TextBlock
            {
                Text = (Validation(s) != null ? "⚠ " : "") + DisplayTrigger(s),
                FontWeight = FontWeights.Bold
            });
            row.Children.Add(new TextBlock
            {
                Text = s.Description.Length > 0 ? s.Description : FirstLine(s.Expansion),
                Foreground = System.Windows.Media.Brushes.Gray, FontSize = 11,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
            _list.Items.Add(row);
        }
        _count.Text = _store.Snippets.Count.ToString();
        _list.SelectedIndex = _selectedId is Guid id ? _filtered.FindIndex(s => s.Id == id) : -1;
        _rebuilding = false;
        LoadDetail();
    }

    private void Select(Guid id)
    {
        _selectedId = id;
        RefreshList();
    }

    private TextSnippet? SelectedSnippet()
        => _selectedId is Guid id ? _store.Snippets.FirstOrDefault(s => s.Id == id) : null;

    // MARK: Editing

    private void LoadDetail()
    {
        var snip = SelectedSnippet();
        bool has = snip != null;
        _deleteButton.IsEnabled = has;
        _duplicateButton.IsEnabled = has;
        if (snip is null)
        {
            _detail.Content = _emptyPane;
            return;
        }
        _detail.Content = _editorPane;
        _loading = true;
        _triggerBox.Text = snip.Trigger;
        _descriptionBox.Text = snip.Description;
        _expansionBox.Text = snip.Expansion;
        _loading = false;
        UpdateDerived(snip);
    }

    private void EditField(Action<TextSnippet> apply)
    {
        if (_loading) return;
        var snip = SelectedSnippet();
        if (snip is null) return;
        apply(snip);
        UpdateDerived(snip);
    }

    private void UpdateDerived(TextSnippet snip)
    {
        string? problem = Validation(snip);
        _validation.Text = problem ?? "";
        _validation.Visibility = problem == null ? Visibility.Collapsed : Visibility.Visible;
        _preview.Text = snip.ResolvedExpansion();
        _insertButton.IsEnabled = problem == null;
    }

    /// <summary>Parity with macOS: a snippet is usable when it has a unique,
    /// whitespace-free trigger and a non-empty expansion.</summary>
    private string? Validation(TextSnippet s)
    {
        string t = s.Trigger.Trim();
        if (t.Length == 0) return "A trigger is required — it's the word you type before pressing Tab.";
        if (t.Any(char.IsWhiteSpace)) return "Triggers can't contain spaces or newlines.";
        if (_store.Snippets.Any(o => o.Id != s.Id && o.Trigger == s.Trigger))
            return $"\"{s.Trigger}\" is already used by another snippet.";
        if (s.Expansion.Trim().Length == 0) return "The expansion is empty — this snippet would insert nothing.";
        return null;
    }

    // MARK: Actions

    private void AddSnippet()
    {
        var s = new TextSnippet(UniqueTrigger("new"), "", "");
        _store.Snippets.Add(s);
        _filter.Text = "";
        Select(s.Id);
        _triggerBox.Focus();
        _triggerBox.CaretIndex = _triggerBox.Text.Length;
    }

    private void DuplicateSelected()
    {
        var s = SelectedSnippet();
        if (s is null) return;
        int idx = _store.Snippets.IndexOf(s);
        var copy = new TextSnippet(UniqueTrigger(s.Trigger), s.Expansion, s.Description);
        _store.Snippets.Insert(idx + 1, copy);
        _filter.Text = "";
        Select(copy.Id);
    }

    private void ConfirmDeleteSelected()
    {
        var s = SelectedSnippet();
        if (s is null) return;
        var result = MessageBox.Show(this,
            $"\"{DisplayTrigger(s)}\" will be removed. This can't be undone.",
            "Delete Snippet?", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (result != MessageBoxResult.OK) return;
        int idx = _store.Snippets.IndexOf(s);
        _store.Snippets.RemoveAt(idx);
        if (_store.Snippets.Count > 0)
            _selectedId = _store.Snippets[Math.Min(idx, _store.Snippets.Count - 1)].Id;
        else
            _selectedId = null;
        RefreshList();
    }

    private void RestoreDefaults()
    {
        var result = MessageBox.Show(this,
            "Every snippet in the list will be replaced by the built-in set.",
            "Restore Default Snippets?", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (result != MessageBoxResult.OK) return;
        _store.Snippets.Clear();
        foreach (var s in TextSnippet.Defaults()) _store.Snippets.Add(s);
        _filter.Text = "";
        _selectedId = _store.Snippets.Count > 0 ? _store.Snippets[0].Id : null;
        RefreshList();
    }

    private void InsertSelected()
    {
        var s = SelectedSnippet();
        if (s is null || Validation(s) != null) return;
        _store.SaveSnippets();
        _onInsert(s);
        DialogResult = true;
    }

    // MARK: Helpers

    private string UniqueTrigger(string baseTrigger)
    {
        string t = baseTrigger;
        int n = 2;
        while (_store.Snippets.Any(s => s.Trigger == t)) t = $"{baseTrigger}{n++}";
        return t;
    }

    private static string DisplayTrigger(TextSnippet s)
        => s.Trigger.Length == 0 ? "(no trigger)" : s.Trigger;

    private static string FirstLine(string text)
    {
        int i = text.IndexOf('\n');
        string s = (i < 0 ? text : text[..i]).Trim();
        return s.Length == 0 ? "(empty)" : s;
    }
}

/// <summary>Minimal settings (parity with macOS SettingsSheet, Ctrl+,).</summary>
public sealed class SettingsWindow : Window
{
    public SettingsWindow(DocumentStore store)
    {
        var s = store.Settings;
        Title = "Settings";
        Width = 440;
        Height = 480;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        ResizeMode = ResizeMode.NoResize;

        var panel = new StackPanel { Margin = new Thickness(20) };
        panel.Children.Add(new TextBlock { Text = "Settings", FontWeight = FontWeights.Bold, Margin = new Thickness(0, 0, 0, 8) });

        // Appearance
        panel.Children.Add(new TextBlock { Text = "Appearance" });
        var appearance = new ComboBox { Margin = new Thickness(0, 2, 0, 8) };
        appearance.Items.Add("System"); appearance.Items.Add("Light"); appearance.Items.Add("Dark");
        appearance.SelectedIndex = (int)s.Appearance;
        appearance.SelectionChanged += (_, _) => s.Appearance = (AppSettings.AppearanceMode)appearance.SelectedIndex;
        panel.Children.Add(appearance);

        // Font
        panel.Children.Add(new TextBlock { Text = "Font" });
        var font = new ComboBox { Margin = new Thickness(0, 2, 0, 4) };
        foreach (string f in new[] { "Cascadia Mono", "Cascadia Code", "Consolas", "Courier New", "Segoe UI", "Arial" })
            font.Items.Add(f);
        font.Text = s.FontName;
        font.IsEditable = true;
        font.SelectionChanged += (_, _) => { if (font.SelectedItem is string f) s.FontName = f; };
        font.LostFocus += (_, _) => { if (!string.IsNullOrWhiteSpace(font.Text)) s.FontName = font.Text; };
        panel.Children.Add(font);

        var sizeRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 8) };
        sizeRow.Children.Add(new TextBlock { Text = "Size", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var size = new Slider { Minimum = 9, Maximum = 28, Value = s.FontSize, Width = 200, TickFrequency = 1, IsSnapToTickEnabled = true };
        var sizeLabel = new TextBlock { Text = ((int)s.FontSize).ToString(), Width = 30, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        size.ValueChanged += (_, _) => { s.FontSize = size.Value; sizeLabel.Text = ((int)size.Value).ToString(); };
        sizeRow.Children.Add(size); sizeRow.Children.Add(sizeLabel);
        panel.Children.Add(sizeRow);

        CheckBox Cb(string label, bool value, Action<bool> set)
        {
            var cb = new CheckBox { Content = label, IsChecked = value, Margin = new Thickness(0, 2, 0, 2) };
            cb.Checked += (_, _) => set(true);
            cb.Unchecked += (_, _) => set(false);
            panel.Children.Add(cb);
            return cb;
        }

        Cb("Wrap long lines (Alt+Ctrl+L)", s.WrapLines, v => s.WrapLines = v);
        Cb("Show line numbers", s.ShowLineNumbers, v => s.ShowLineNumbers = v);
        Cb("Spellcheck (Alt+Ctrl+K)", s.Spellcheck, v => s.Spellcheck = v);
        Cb("Auto-save", s.AutoSaveEnabled, v => s.AutoSaveEnabled = v);

        var autoRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
        autoRow.Children.Add(new TextBlock { Text = "Autosave every", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var auto = new Slider { Minimum = 2, Maximum = 60, Value = s.AutoSaveInterval, Width = 180, TickFrequency = 1, IsSnapToTickEnabled = true };
        var autoLabel = new TextBlock { Text = $"{(int)s.AutoSaveInterval}s", Width = 36, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        auto.ValueChanged += (_, _) => { s.AutoSaveInterval = auto.Value; autoLabel.Text = $"{(int)auto.Value}s"; store.RestartAutosave(); };
        autoRow.Children.Add(auto); autoRow.Children.Add(autoLabel);
        panel.Children.Add(autoRow);

        var tabRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        tabRow.Children.Add(new TextBlock { Text = "Tab width", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
        var tab = new Slider { Minimum = 2, Maximum = 8, Value = s.TabWidth, Width = 180, TickFrequency = 1, IsSnapToTickEnabled = true };
        var tabLabel = new TextBlock { Text = s.TabWidth.ToString(), Width = 30, Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        tab.ValueChanged += (_, _) => { s.TabWidth = (int)tab.Value; tabLabel.Text = ((int)tab.Value).ToString(); };
        tabRow.Children.Add(tab); tabRow.Children.Add(tabLabel);
        panel.Children.Add(tabRow);

        var done = new Button { Content = "Done", Width = 80, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0), IsDefault = true };
        done.Click += (_, _) => DialogResult = true;
        panel.Children.Add(done);

        Content = new ScrollViewer { Content = panel };
    }
}
