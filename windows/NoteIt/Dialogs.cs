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

/// <summary>Snippets manager + picker (parity with macOS SnippetsSheet, Ctrl+J).</summary>
public sealed class SnippetsWindow : Window
{
    private readonly DocumentStore _store;
    private readonly Action<TextSnippet> _onInsert;
    private readonly ListBox _list;
    private readonly TextBox _newTrigger;
    private readonly TextBox _newExpansion;

    public SnippetsWindow(DocumentStore store, Action<TextSnippet> onInsert)
    {
        _store = store;
        _onInsert = onInsert;
        Title = "Text Snippets";
        Width = 580;
        Height = 420;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;

        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock { Text = "Text Snippets", FontWeight = FontWeights.Bold });
        panel.Children.Add(new TextBlock
        {
            Text = "Type a trigger then press Tab to expand. {date} and {time} auto-fill.",
            Foreground = System.Windows.Media.Brushes.Gray,
            Margin = new Thickness(0, 0, 0, 8)
        });

        _list = new ListBox { Height = 200 };
        _list.MouseDoubleClick += (_, _) => InsertSelected();
        panel.Children.Add(_list);

        var addRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        _newTrigger = new TextBox { Width = 110, Margin = new Thickness(0, 0, 6, 0) };
        _newTrigger.SetValue(TextBox.ToolTipProperty, "trigger");
        _newExpansion = new TextBox { Width = 300, Margin = new Thickness(0, 0, 6, 0) };
        _newExpansion.SetValue(TextBox.ToolTipProperty, "expansion…");
        var add = new Button { Content = "Add", Width = 60 };
        add.Click += (_, _) =>
        {
            string t = _newTrigger.Text.Trim();
            if (t.Length == 0 || _newExpansion.Text.Length == 0) return;
            _store.Snippets.Add(new TextSnippet(t, _newExpansion.Text));
            _newTrigger.Text = ""; _newExpansion.Text = "";
            Refresh();
        };
        addRow.Children.Add(_newTrigger); addRow.Children.Add(_newExpansion); addRow.Children.Add(add);
        panel.Children.Add(addRow);

        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 8, 0, 0) };
        var insert = new Button { Content = "Insert", Width = 75, Margin = new Thickness(0, 0, 6, 0) };
        insert.Click += (_, _) => InsertSelected();
        var del = new Button { Content = "Delete", Width = 75, Margin = new Thickness(0, 0, 6, 0) };
        del.Click += (_, _) =>
        {
            int i = _list.SelectedIndex;
            if (i >= 0 && i < _store.Snippets.Count) { _store.Snippets.RemoveAt(i); Refresh(); }
        };
        var done = new Button { Content = "Done", Width = 75, IsDefault = true };
        done.Click += (_, _) => DialogResult = true;
        btnRow.Children.Add(insert); btnRow.Children.Add(del); btnRow.Children.Add(done);
        panel.Children.Add(btnRow);

        Content = panel;
        Refresh();
    }

    private void Refresh()
    {
        _list.Items.Clear();
        foreach (var s in _store.Snippets)
            _list.Items.Add($"{s.Trigger}   →   {s.ResolvedExpansion()}");
        if (_list.Items.Count > 0 && _list.SelectedIndex < 0) _list.SelectedIndex = 0;
    }

    private void InsertSelected()
    {
        int i = _list.SelectedIndex;
        if (i >= 0 && i < _store.Snippets.Count)
        {
            _onInsert(_store.Snippets[i]);
            DialogResult = true;
        }
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
