using Microsoft.Win32;
using System.Collections.Specialized;
using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;

namespace NoteIt;

public partial class MainWindow : Window
{
    private readonly DocumentStore _store = App.Store;
    private bool _syncing;      // true while pushing model -> editor
    private bool _updatingTabs; // true while rebuilding tab bar

    public MainWindow()
    {
        InitializeComponent();
        DataContext = _store;
        App.RegisterWindow();

        _store.Documents.CollectionChanged += (_, _) => { RebuildTabs(); RefreshRecentMenu(); };
        _store.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(DocumentStore.SelectedDocument) || e.PropertyName == nameof(DocumentStore.SelectedId))
                Dispatcher.Invoke(LoadSelectedDocument);
        };
        _store.Settings.PropertyChanged += (_, e) => Dispatcher.Invoke(() =>
        {
            if (e.PropertyName is null) return;
            ApplySettingsToEditor();
            if (e.PropertyName == nameof(AppSettings.Appearance)) App.ApplyTheme(_store.Settings.Appearance);
            UpdateStatusBar();
        });
        _store.Search.PropertyChanged += (_, _) => Dispatcher.Invoke(UpdateMatchCount);

        Loaded += (_, _) =>
        {
            ApplySettingsToEditor();
            LoadSelectedDocument();
            RebuildTabs();
            RefreshRecentMenu();
            UpdateStatusBar();
            HookEditorScrollSync();
            DataObject.AddPastingHandler(Editor, OnPaste);
            Editor.Focus();
        };
        SourceInitialized += (_, _) => App.OnWindowSourceInitialized(this);
        StateChanged += OnWindowStateChanged;
        PreviewKeyDown += OnWindowPreviewKeyDown;
        Closing += (_, e) =>
        {
            App.UnregisterWindow();
            _store.AutosaveTick();
        };
    }

    // MARK: - Window caption / title bar
    private void OnTitleBarMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            if (e.ClickCount >= 2)
            {
                // Double-click to maximize/restore
                ToggleMaximize();
                e.Handled = true;
                return;
            }
            // Single click on the title bar (not on a tab) = drag
            if (e.OriginalSource is ScrollViewer || e.OriginalSource is System.Windows.Controls.Grid)
                this.DragMove();
        }
    }

    private void OnMinimize(object s, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void OnMaximizeRestore(object s, RoutedEventArgs e) => ToggleMaximize();

    private void ToggleMaximize()
    {
        if (WindowState == WindowState.Maximized)
            WindowState = WindowState.Normal;
        else
            WindowState = WindowState.Maximized;
    }

    private void OnCloseWindow(object s, RoutedEventArgs e)
    {
        _store.AutosaveTick();
        Close();
    }

    private void OnWindowStateChanged(object? sender, EventArgs e)
    {
        if (WindowState == WindowState.Maximized)
        {
            MaxButton.Visibility = Visibility.Collapsed;
            RestoreButton.Visibility = Visibility.Visible;
        }
        else
        {
            MaxButton.Visibility = Visibility.Visible;
            RestoreButton.Visibility = Visibility.Collapsed;
        }
    }

    // MARK: - RichTextBox <-> document sync (plain text)
    private string GetEditorText()
    {
        var range = new TextRange(Editor.Document.ContentStart, Editor.Document.ContentEnd);
        string t = range.Text ?? "";
        if (t.EndsWith("\r\n")) t = t[..^2];
        else if (t.EndsWith("\n")) t = t[..^1];
        return t.Replace("\r\n", "\n").Replace("\r", "\n");
    }

    private int GetCaretOffset()
    {
        try
        {
            string before = new TextRange(Editor.Document.ContentStart, Editor.CaretPosition).Text ?? "";
            return before.Replace("\r\n", "\n").Replace("\r", "\n").Length;
        }
        catch { return 0; }
    }

    private void SetCaretOffset(int offset)
    {
        try
        {
            TextPointer p = Editor.Document.ContentStart;
            int remaining = Math.Max(0, offset);
            while (remaining > 0 && p != null)
            {
                TextPointer? next = p.GetNextInsertionPosition(LogicalDirection.Forward);
                if (next is null) break;
                p = next;
                remaining--;
            }
            Editor.CaretPosition = p ?? Editor.Document.ContentEnd;
        }
        catch { }
    }

    private void SelectRange(int start, int length)
    {
        try
        {
            TextPointer? s = OffsetToPointer(start);
            TextPointer? e = OffsetToPointer(start + length);
            if (s is null || e is null) return;
            {
                Editor.Selection.Select(s, e);
                Editor.CaretPosition = e;
                Editor.Focus();
            }
        }
        catch { }
    }

    private TextPointer? OffsetToPointer(int offset)
    {
        TextPointer p = Editor.Document.ContentStart;
        int remaining = Math.Max(0, offset);
        while (remaining > 0)
        {
            TextPointer? next = p.GetNextInsertionPosition(LogicalDirection.Forward);
            if (next is null) return Editor.Document.ContentEnd;
            p = next;
            remaining--;
        }
        return p;
    }

    private void SetEditorText(string text)
    {
        _syncing = true;
        try
        {
            int caret = Math.Min(GetCaretOffset(), text.Length);
            Editor.Document.Blocks.Clear();
            var para = new Paragraph(new Run(text ?? ""))
            {
                Margin = new Thickness(0),
                LineHeight = double.NaN,
            };
            ApplyTabStops(para);
            Editor.Document.Blocks.Add(para);
            ApplySettingsToEditor();
            SetCaretOffset(caret);
            UpdateGutter();
        }
        finally { _syncing = false; }
    }

    private void LoadSelectedDocument()
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        if (GetEditorText() != doc.Text.Replace("\r\n", "\n"))
            SetEditorText(doc.Text);
        ApplySettingsToEditor();
        UpdateGutter();
        UpdateStatusBar();
        SyncStatusChecks();
        RebuildTabsSelection();
        ClearHighlight();
        UpdateMatchCount();
    }

    private void PushEditorToDoc()
    {
        var doc = _store.SelectedDocument;
        if (doc is null || _syncing) return;
        string t = GetEditorText();
        if (doc.Text != t)
        {
            doc.Text = t;
            UpdateGutter();
            UpdateStatusBar();
        }
    }

    // MARK: - Editor events
    private void OnEditorTextChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncing) return;
        PushEditorToDoc();
        if (!_store.Search.Query.Equals(""))
            Dispatcher.BeginInvoke(UpdateHighlight, System.Windows.Threading.DispatcherPriority.Background);
        UpdateMatchCount();
    }

    private void OnEditorSelectionChanged(object sender, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        try
        {
            string before = new TextRange(Editor.Document.ContentStart, Editor.CaretPosition).Text ?? "";
            string norm = before.Replace("\r\n", "\n").Replace("\r", "\n");
            var lines = norm.Split('\n');
            doc.CursorLine = lines.Length;
            doc.CursorColumn = (lines[^1].Length) + 1;
        }
        catch { }
        UpdateStatusBar();
    }

    private void OnEditorPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (e.Key == Key.Tab && doc != null)
        {
            e.Handled = true;
            int caret = GetCaretOffset();
            string text = GetEditorText();
            var exp = _store.ExpandTrigger(text, caret);
            if (exp.HasValue)
            {
                string next = text[..exp.Value.Start] + exp.Value.Expansion + text[(exp.Value.Start + exp.Value.Length)..];
                doc.Text = next;
                SetEditorText(next);
                SetCaretOffset(exp.Value.Start + exp.Value.Expansion.Length);
                Editor.Focus();
            }
            else
            {
                string spaces = new(' ', Math.Max(2, Math.Min(8, _store.Settings.TabWidth)));
                int c = GetCaretOffset();
                string t = GetEditorText();
                string next = t[..c] + spaces + t[c..];
                doc.Text = next;
                SetEditorText(next);
                SetCaretOffset(c + spaces.Length);
                Editor.Focus();
            }
            return;
        }
        if (e.Key == Key.Escape && FindBar.Visibility == Visibility.Visible)
        {
            CloseFind();
            e.Handled = true;
        }
    }

    private void OnPaste(object sender, DataObjectPastingEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc != null && !doc.FormattingEnabled)
        {
            if (e.DataObject.GetDataPresent(DataFormats.UnicodeText))
            {
                string? text = e.DataObject.GetData(DataFormats.UnicodeText) as string;
                if (text != null)
                {
                    e.CancelCommand();
                    Editor.Selection.Text = text.Replace("\r\n", "\n");
                    e.Handled = true;
                }
            }
        }
    }

    // MARK: - Drag & Drop file support
    private void OnEditorDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
            e.Effects = DragDropEffects.Copy;
        else
            e.Effects = DragDropEffects.None;
        e.Handled = true;
    }

    private void OnEditorDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            string[] files = (string[])e.Data.GetData(DataFormats.FileDrop);
            foreach (string f in files)
                _store.OpenPath(f);
            LoadSelectedDocument();
            RebuildTabs();
            RefreshRecentMenu();
        }
        e.Handled = true;
    }

    // MARK: - Mouse wheel zoom (Ctrl+Wheel)
    private void OnEditorMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            if (e.Delta > 0)
                _store.Settings.FontSize = Math.Min(28, _store.Settings.FontSize + 1);
            else
                _store.Settings.FontSize = Math.Max(9, _store.Settings.FontSize - 1);
            e.Handled = true;
        }
    }

    // MARK: - Editor context menu
    private void OnEditorContextMenu(object sender, ContextMenuEventArgs e)
    {
        // The context menu is already set in XAML; just ensure it's in the right state
        if (EditorContextMenu != null)
        {
            // Disable paste if clipboard doesn't have text
            foreach (var item in EditorContextMenu.Items)
            {
                if (item is MenuItem mi && mi.Header is string header && header == "Paste")
                {
                    mi.IsEnabled = Clipboard.ContainsText();
                }
            }
        }
    }

    // MARK: - Settings -> editor
    private void ApplySettingsToEditor()
    {
        var s = _store.Settings;
        try
        {
            Editor.FontFamily = new FontFamily(s.FontName);
        }
        catch { Editor.FontFamily = new FontFamily("Consolas"); }
        Editor.FontSize = s.FontSize;
        System.Windows.Controls.SpellCheck.SetIsEnabled(Editor, s.Spellcheck);
        Editor.Document.PageWidth = s.WrapLines ? double.NaN : 10000;
        Editor.HorizontalScrollBarVisibility = s.WrapLines ? ScrollBarVisibility.Disabled : ScrollBarVisibility.Auto;
        foreach (var b in Editor.Document.Blocks.OfType<Paragraph>())
            ApplyTabStops(b);

        GutterText.FontFamily = Editor.FontFamily;
        GutterText.FontSize = Math.Min(Math.Max(s.FontSize - 1, 9), 12);
        GutterColumn.Width = new GridLength(s.ShowLineNumbers ? 48 : 0);
        GutterScroll.Visibility = s.ShowLineNumbers ? Visibility.Visible : Visibility.Collapsed;

        WrapSearchCheck.IsChecked = _store.Search.WrapAround;
        FontText.Text = s.FontName;
    }

    private void ApplyTabStops(Paragraph para)
    {
        // Tab expansion is handled by inserting TabWidth spaces on Tab key
    }

    // MARK: - Gutter (line numbers)
    private void UpdateGutter()
    {
        var doc = _store.SelectedDocument;
        int count = doc?.LineCount ?? 1;
        var sb = new System.Text.StringBuilder();
        for (int i = 1; i <= count; i++)
        {
            if (i > 1) sb.Append('\n');
            sb.Append(i);
        }
        GutterText.Text = sb.ToString();
        int digits = Math.Max(2, count.ToString().Length);
        GutterColumn.Width = new GridLength(_store.Settings.ShowLineNumbers ? digits * 10 + 24 : 0);
    }

    private void HookEditorScrollSync()
    {
        var inner = FindDescendant<System.Windows.Controls.ScrollViewer>(Editor);
        if (inner != null)
            inner.ScrollChanged += (_, e) =>
            {
                if (e.VerticalChange != 0)
                    GutterScroll.ScrollToVerticalOffset(e.VerticalOffset);
            };
    }

    private static T? FindDescendant<T>(DependencyObject root) where T : DependencyObject
    {
        if (root is T t) return t;
        int n = System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);
        for (int i = 0; i < n; i++)
        {
            var c = System.Windows.Media.VisualTreeHelper.GetChild(root, i);
            var r = FindDescendant<T>(c);
            if (r != null) return r;
        }
        return null;
    }

    // MARK: - Tabs
    private void RebuildTabs()
    {
        if (_updatingTabs) return;
        _updatingTabs = true;
        try
        {
            TabsPanel.Children.Clear();
            foreach (var doc in _store.Documents)
            {
                var chip = new Border
                {
                    Margin = new Thickness(0, 0, 2, 0),
                    Padding = new Thickness(10, 4, 4, 4),
                    CornerRadius = new CornerRadius(6, 6, 0, 0),
                    BorderThickness = new Thickness(1, 1, 1, 0),
                    Tag = doc,
                    Cursor = Cursors.Hand,
                };
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                var icon = new TextBlock { Text = doc.FilePath is null ? "\uE7C3" : "\uE8A5",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 10, VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, 6, 0) };
                var label = new TextBlock { Text = doc.DisplayTitle, MaxWidth = 140,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                    VerticalAlignment = VerticalAlignment.Center,
                    FontSize = 12 };
                doc.PropertyChanged += (_, e) =>
                {
                    if (e.PropertyName == nameof(EditorDocument.DisplayTitle))
                        label.Text = doc.DisplayTitle;
                };
                var close = new Button
                {
                    Content = "\uE711",
                    FontFamily = new FontFamily("Segoe Fluent Icons"),
                    FontSize = 8,
                    Width = 20, Height = 20,
                    Margin = new Thickness(8, 0, 0, 0),
                    ToolTip = "Close tab (Ctrl+W)",
                    Background = Brushes.Transparent,
                    BorderThickness = new Thickness(0)
                };
                close.Click += (_, _) => CloseTab(doc);
                sp.Children.Add(icon); sp.Children.Add(label); sp.Children.Add(close);
                chip.Child = sp;
                chip.MouseLeftButtonUp += (_, _) => { _store.Select(doc); LoadSelectedDocument(); };
                TabsPanel.Children.Add(chip);
            }
            RebuildTabsSelection();
        }
        finally { _updatingTabs = false; }
    }

    private void RebuildTabsSelection()
    {
        var sel = _store.SelectedDocument;
        foreach (Border chip in TabsPanel.Children.OfType<Border>())
        {
            bool isSel = sel != null && chip.Tag == sel;
            chip.Background = isSel
                ? (SolidColorBrush)FindResource("NoteItTabSelectedBackground")
                : Brushes.Transparent;
            chip.BorderBrush = isSel
                ? (SolidColorBrush)FindResource("NoteItSeparator")
                : new SolidColorBrush(Color.FromArgb(0, 0, 0, 0));
        }
    }

    private void CloseTab(EditorDocument doc)
    {
        if (_store.SelectedDocument == doc) PushEditorToDoc();
        if (doc.IsDirty)
        {
            var r = MessageBox.Show($"Save changes to \"{doc.Title}\"?", "NoteIt",
                MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
            if (r == MessageBoxResult.Cancel) return;
            if (r == MessageBoxResult.Yes)
            {
                if (!SaveDoc(doc, doc.FilePath is null)) return;
            }
        }
        _store.RemoveDocument(doc);
        LoadSelectedDocument();
        RebuildTabs();
    }

    // MARK: - Status bar
    private void UpdateStatusBar()
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        CursorText.Text = $"Ln {doc.CursorLine}, Col {doc.CursorColumn}";
        WordText.Text = $"{doc.WordCount} words";
        LineText.Text = $"{doc.LineCount} lines";
        SavedText.Text = doc.IsDirty ? "\u25CF Unsaved" : "Saved";
        SavedText.Foreground = doc.IsDirty ? Brushes.Orange : Brushes.Gray;
        FileText.Text = doc.FilePath is string fp ? System.IO.Path.GetFileName(fp) : "";
        FileText.ToolTip = doc.FilePath;
    }

    private void SyncStatusChecks()
    {
        var doc = _store.SelectedDocument;
        WrapCheck.IsChecked = _store.Settings.WrapLines;
        SpellCheck.IsChecked = _store.Settings.Spellcheck;
        FormatCheck.IsChecked = doc?.FormattingEnabled ?? false;
    }

    private void OnWrapChecked(object s, RoutedEventArgs e) => _store.Settings.WrapLines = WrapCheck.IsChecked == true;
    private void OnSpellChecked(object s, RoutedEventArgs e) => _store.Settings.Spellcheck = SpellCheck.IsChecked == true;
    private void OnFormatChecked(object s, RoutedEventArgs e)
    {
        if (_store.SelectedDocument != null)
            _store.SelectedDocument.FormattingEnabled = FormatCheck.IsChecked == true;
    }

    // MARK: - File actions
    private void OnNewTab(object s, RoutedEventArgs e) { PushEditorToDoc(); _store.NewDocument(); LoadSelectedDocument(); RebuildTabs(); Editor.Focus(); }
    private void OnNewWindow(object s, RoutedEventArgs e) { PushEditorToDoc(); new MainWindow().Show(); }
    private void OnOpen(object s, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Multiselect = true, Filter = "Text files (*.txt;*.md;*.swift;*.cs;*.xaml)|*.txt;*.md;*.swift;*.cs;*.xaml|All files (*.*)|*.*" };
        if (dlg.ShowDialog() == true)
            foreach (string f in dlg.FileNames) _store.OpenPath(f);
        LoadSelectedDocument(); RebuildTabs(); RefreshRecentMenu();
    }

    private bool SaveDoc(EditorDocument doc, bool saveAs)
    {
        PushEditorToDoc();
        string? path = doc.FilePath;
        if (saveAs || path is null)
        {
            var dlg = new SaveFileDialog
            {
                Filter = "Text files (*.txt)|*.txt|All files (*.*)|*.*",
                FileName = doc.FilePath is string fp ? System.IO.Path.GetFileName(fp) : "Untitled.txt"
            };
            if (dlg.ShowDialog() != true) return false;
            path = dlg.FileName;
        }
        bool ok = _store.SaveToPath(doc, path);
        UpdateStatusBar(); RebuildTabs();
        return ok;
    }

    private void OnSave(object s, RoutedEventArgs e) { if (_store.SelectedDocument != null) SaveDoc(_store.SelectedDocument, false); }
    private void OnSaveAs(object s, RoutedEventArgs e) { if (_store.SelectedDocument != null) SaveDoc(_store.SelectedDocument, true); }
    private void OnSaveAll(object s, RoutedEventArgs e)
    {
        PushEditorToDoc();
        foreach (var d in _store.Documents.Where(d => d.IsDirty).ToList())
        {
            if (d.FilePath is string fp) _store.SaveToPath(d, fp);
        }
        var untitled = _store.Documents.FirstOrDefault(d => d.IsDirty && d.FilePath is null);
        if (untitled != null) { _store.Select(untitled); LoadSelectedDocument(); SaveDoc(untitled, true); }
        UpdateStatusBar(); RebuildTabs();
    }
    private void OnRevert(object s, RoutedEventArgs e)
    {
        if (_store.SelectedDocument is { } doc)
        {
            _store.Revert(doc);
            SetEditorText(doc.Text);
            UpdateStatusBar();
        }
    }
    private void OnCloseTab(object s, RoutedEventArgs e) { if (_store.SelectedDocument != null) CloseTab(_store.SelectedDocument); }
    private void OnExit(object s, RoutedEventArgs e) { _store.AutosaveTick(); Application.Current.Shutdown(); }

    private void OnExportPdf(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        PushEditorToDoc();
        var dlg = new SaveFileDialog { Filter = "PDF (*.pdf)|*.pdf", FileName = doc.Title + ".pdf" };
        if (dlg.ShowDialog() != true) return;
        try { DocumentStore.ExportPdf(doc, dlg.FileName); }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }
    private void OnExportText(object s, RoutedEventArgs e) { if (_store.SelectedDocument != null) SaveDoc(_store.SelectedDocument, true); }
    private void OnPrint(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        PushEditorToDoc();
        var dlg = new PrintDialog();
        if (dlg.ShowDialog() != true) return;
        try
        {
            var flow = new FlowDocument(new Paragraph(new Run(doc.Text)))
            {
                FontFamily = Editor.FontFamily,
                FontSize = Editor.FontSize,
                PageWidth = dlg.PrintableAreaWidth,
            };
            dlg.PrintDocument(((IDocumentPaginatorSource)flow).DocumentPaginator, $"NoteIt - {doc.Title}");
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Print failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    // MARK: - Find / Replace
    private void OnShowFind(object s, RoutedEventArgs e) { FindBar.Visibility = Visibility.Visible; ReplaceRow.Visibility = Visibility.Collapsed; FindBox.Focus(); FindBox.SelectAll(); }
    private void OnShowReplace(object s, RoutedEventArgs e) { FindBar.Visibility = Visibility.Visible; ReplaceRow.Visibility = Visibility.Visible; FindBox.Focus(); }
    private void OnToggleReplaceBar(object s, RoutedEventArgs e) => ReplaceRow.Visibility = ReplaceRow.Visibility == Visibility.Visible ? Visibility.Collapsed : Visibility.Visible;
    private void OnCloseFind(object s, RoutedEventArgs e) => CloseFind();
    private void CloseFind()
    {
        _store.Search.Query = "";
        FindBox.Text = "";
        ClearHighlight();
        UpdateMatchCount();
        FindBar.Visibility = Visibility.Collapsed;
        ReplaceRow.Visibility = Visibility.Collapsed;
        Editor.Focus();
    }

    private void OnFindTextChanged(object s, TextChangedEventArgs e)
    {
        _store.Search.Query = FindBox.Text;
        UpdateHighlight();
        UpdateMatchCount();
    }
    private void OnReplaceTextChanged(object s, TextChangedEventArgs e) => _store.Search.Replacement = ReplaceBox.Text;
    private void OnSearchOptChanged(object s, RoutedEventArgs e)
    {
        _store.Search.CaseSensitive = CaseBtn.IsChecked == true;
        _store.Search.UseRegex = RegexBtn.IsChecked == true;
        _store.Search.WholeWord = WordBtn.IsChecked == true;
        _store.Search.WrapAround = WrapSearchCheck.IsChecked != false;
        UpdateHighlight();
        UpdateMatchCount();
    }

    private void UpdateMatchCount()
    {
        var doc = _store.SelectedDocument;
        if (doc is null || string.IsNullOrEmpty(_store.Search.Query)) { MatchCount.Text = ""; return; }
        int n = _store.MatchCount(_store.Search.Query, doc.Text);
        MatchCount.Text = $"{n} match{(n == 1 ? "" : "es")}";
    }

    private void OnFindNext(object s, RoutedEventArgs e) => FindNext();
    private void OnFindPrev(object s, RoutedEventArgs e) => FindPrevious();

    private void FindNext()
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        PushEditorToDoc();
        var m = _store.FindNextMatch(doc.Text, GetCaretOffset());
        if (m.HasValue) SelectRange(m.Value.Start, m.Value.Length);
        else SystemSounds.Beep.Play();
    }

    private void FindPrevious()
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        PushEditorToDoc();
        var m = _store.FindPreviousMatch(doc.Text, GetCaretOffset());
        if (m.HasValue) SelectRange(m.Value.Start, m.Value.Length);
        else SystemSounds.Beep.Play();
    }

    private void OnReplaceCurrent(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        string sel = Editor.Selection.Text ?? "";
        if (!string.IsNullOrEmpty(sel) && _store.SelectedTextMatches(sel.Replace("\r\n", "\n")))
        {
            Editor.Selection.Text = _store.Search.Replacement;
            PushEditorToDoc();
        }
        FindNext();
    }

    private void OnReplaceAll(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null || string.IsNullOrEmpty(_store.Search.Query)) return;
        PushEditorToDoc();
        string result = _store.ReplaceAllIn(doc.Text);
        if (result != doc.Text)
        {
            doc.Text = result;
            SetEditorText(result);
            UpdateGutter(); UpdateStatusBar();
        }
        else SystemSounds.Beep.Play();
    }

    private void UpdateHighlight()
    {
        ClearHighlight();
        var doc = _store.SelectedDocument;
        if (doc is null || string.IsNullOrEmpty(_store.Search.Query)) return;
        try
        {
            var ranges = _store.RangesOf(_store.Search.Query, doc.Text).Take(500).ToList();
            var brush = new SolidColorBrush(Color.FromArgb(90, 255, 235, 59));
            brush.Freeze();
            foreach (var (start, len) in ranges)
            {
                if (len == 0) continue;
                var s = OffsetToPointer(start);
                var en = OffsetToPointer(start + len);
                if (s is null || en is null) continue;
                var range = new TextRange(s, en);
                range.ApplyPropertyValue(TextElement.BackgroundProperty, brush);
            }
        }
        catch { }
    }

    private void ClearHighlight()
    {
        try
        {
            var full = new TextRange(Editor.Document.ContentStart, Editor.Document.ContentEnd);
            full.ApplyPropertyValue(TextElement.BackgroundProperty, Brushes.Transparent);
        }
        catch { }
    }

    // MARK: - GoTo / QuickOpen / Snippets / Settings
    private void OnGoToLine(object s, RoutedEventArgs e)
    {
        var dlg = new GoToLineWindow { Owner = this };
        if (dlg.ShowDialog() != true || !dlg.LineNumber.HasValue) return;
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        PushEditorToDoc();
        int? off = DocumentStore.OffsetOfLine(doc.Text, dlg.LineNumber.Value);
        if (off is null) { SystemSounds.Beep.Play(); return; }
        int len = DocumentStore.LineLength(doc.Text, off.Value);
        SelectRange(off.Value, len);
    }

    private void OnQuickOpen(object s, RoutedEventArgs e)
    {
        var dlg = new QuickOpenWindow(_store) { Owner = this };
        if (dlg.ShowDialog() == true && dlg.ChosenPath != null)
            _store.OpenPath(dlg.ChosenPath);
        LoadSelectedDocument(); RebuildTabs(); RefreshRecentMenu();
    }

    private void OnSnippets(object s, RoutedEventArgs e)
    {
        var dlg = new SnippetsWindow(_store, InsertSnippetIntoEditor) { Owner = this };
        dlg.ShowDialog();
    }

    private void InsertSnippetIntoEditor(TextSnippet snippet)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        string expansion = snippet.ResolvedExpansion();
        try
        {
            Editor.Selection.Text = expansion;
        }
        catch
        {
            int c = GetCaretOffset();
            string t = GetEditorText();
            string next = t[..c] + expansion + t[c..];
            doc.Text = next;
            SetEditorText(next);
            SetCaretOffset(c + expansion.Length);
            return;
        }
        PushEditorToDoc();
        Editor.Focus();
    }

    private void OnSettings(object s, RoutedEventArgs e)
    {
        var dlg = new SettingsWindow(_store) { Owner = this };
        dlg.ShowDialog();
        ApplySettingsToEditor();
        UpdateStatusBar();
    }

    private void OnAbout(object s, RoutedEventArgs e)
        => MessageBox.Show("NoteIt — lightweight native Windows text editor.\nWPF port of the macOS app, same features, Ctrl-based shortcuts.",
            "About NoteIt", MessageBoxButton.OK, MessageBoxImage.Information);

    private void RefreshRecentMenu()
    {
        RecentMenu.Items.Clear();
        if (_store.RecentFiles.Count == 0)
        {
            RecentMenu.Items.Add(new MenuItem { Header = "No Recent Files", IsEnabled = false });
            return;
        }
        foreach (string p in _store.RecentFiles.Take(10).ToList())
        {
            var mi = new MenuItem { Header = System.IO.Path.GetFileName(p), ToolTip = p };
            mi.Click += (_, _) => { _store.OpenPath(p); LoadSelectedDocument(); RebuildTabs(); };
            RecentMenu.Items.Add(mi);
        }
        RecentMenu.Items.Add(new Separator());
        var clear = new MenuItem { Header = "Clear Menu" };
        clear.Click += (_, _) => { _store.ClearRecents(); RefreshRecentMenu(); };
        RecentMenu.Items.Add(clear);
    }

    // MARK: - View actions
    private void OnToggleWrap(object s, RoutedEventArgs e) => _store.Settings.WrapLines = !_store.Settings.WrapLines;
    private void OnToggleLineNumbers(object s, RoutedEventArgs e) => _store.Settings.ShowLineNumbers = !_store.Settings.ShowLineNumbers;
    private void OnToggleSpell(object s, RoutedEventArgs e) => _store.Settings.Spellcheck = !_store.Settings.Spellcheck;
    private void OnThemeSystem(object s, RoutedEventArgs e) => _store.Settings.Appearance = AppSettings.AppearanceMode.System;
    private void OnThemeLight(object s, RoutedEventArgs e) => _store.Settings.Appearance = AppSettings.AppearanceMode.Light;
    private void OnThemeDark(object s, RoutedEventArgs e) => _store.Settings.Appearance = AppSettings.AppearanceMode.Dark;
    private void OnFontBigger(object s, RoutedEventArgs e) => _store.Settings.FontSize = Math.Min(28, _store.Settings.FontSize + 1);
    private void OnFontSmaller(object s, RoutedEventArgs e) => _store.Settings.FontSize = Math.Max(9, _store.Settings.FontSize - 1);
    private void OnFontReset(object s, RoutedEventArgs e) => _store.Settings.FontSize = 14;

    private void EnsureFormattingEnabled(string op)
    {
        var doc = _store.SelectedDocument;
        if (doc != null && !doc.FormattingEnabled)
        {
            SystemSounds.Beep.Play();
            MessageBox.Show("Enable \"Format\" in the status bar to use Bold / Italic.",
                "Plain-text only mode", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void OnBold(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        if (!doc.FormattingEnabled) { EnsureFormattingEnabled("Bold"); return; }
        EditingCommands.ToggleBold.Execute(null, Editor);
    }
    private void OnItalic(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        if (!doc.FormattingEnabled) { EnsureFormattingEnabled("Italic"); return; }
        EditingCommands.ToggleItalic.Execute(null, Editor);
    }
    private void OnUnderline(object s, RoutedEventArgs e)
    {
        var doc = _store.SelectedDocument;
        if (doc is null) return;
        if (!doc.FormattingEnabled) { EnsureFormattingEnabled("Underline"); return; }
        EditingCommands.ToggleUnderline.Execute(null, Editor);
    }

    // MARK: - Global shortcuts (Ctrl-based parity for macOS Cmd shortcuts)
    private void OnWindowPreviewKeyDown(object sender, KeyEventArgs e)
    {
        bool ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        bool shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        bool alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);
        if (!ctrl) return;

        var doc = _store.SelectedDocument;
        switch (e.Key)
        {
            case Key.T: _store.NewDocument(); LoadSelectedDocument(); RebuildTabs(); e.Handled = true; break;
            case Key.N when shift: new MainWindow().Show(); e.Handled = true; break;
            case Key.N when !shift: _store.NewDocument(); LoadSelectedDocument(); RebuildTabs(); e.Handled = true; break;
            case Key.O: OnOpen(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.P when shift: OnPrint(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.P when !shift: OnQuickOpen(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.S when shift: if (doc != null) SaveDoc(doc, true); e.Handled = true; break;
            case Key.S when alt: OnSaveAll(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.S: if (doc != null) SaveDoc(doc, false); e.Handled = true; break;
            case Key.W: if (doc != null) CloseTab(doc); e.Handled = true; break;
            case Key.F when alt: OnShowReplace(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.F: OnShowFind(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.H: OnShowReplace(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.G when shift: FindPrevious(); e.Handled = true; break;
            case Key.G: FindNext(); e.Handled = true; break;
            case Key.L when alt: _store.Settings.WrapLines = !_store.Settings.WrapLines; e.Handled = true; break;
            case Key.L when shift: _store.Settings.ShowLineNumbers = !_store.Settings.ShowLineNumbers; e.Handled = true; break;
            case Key.L: OnGoToLine(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.J: OnSnippets(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.K when alt: _store.Settings.Spellcheck = !_store.Settings.Spellcheck; e.Handled = true; break;
            case Key.D when alt: _store.Settings.Appearance = AppSettings.AppearanceMode.Dark; e.Handled = true; break;
            case Key.E when shift: OnExportPdf(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.OemPlus: OnFontBigger(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.OemMinus: OnFontSmaller(this, new RoutedEventArgs()); e.Handled = true; break;
            case Key.D0: OnFontReset(this, new RoutedEventArgs()); e.Handled = true; break;
        }
        if (e.Key == Key.OemComma) { OnSettings(this, new RoutedEventArgs()); e.Handled = true; }
    }
}
