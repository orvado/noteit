# NoteIt for Windows — native WPF port

Truly native Windows version of the macOS NoteIt text editor, living on the
`windows` branch. **C# + WPF on .NET 9** was chosen because it is:

- **Native**: DirectX hardware-accelerated rendering, native file dialogs,
  native spellchecker, native printing — no Electron/WebView.
- **Fast**: cold start ~instant, memory in the tens of MB, same as the macOS app.
- **Buildable today**: uses only the .NET SDK + `Microsoft.WindowsDesktop.App`
  runtime already installed on this machine. Zero NuGet dependencies.

## What makes it a native Windows app

Beyond being a faithful WPF port of the macOS editor, this version goes further
to look and act like a genuine Windows 11 application:

| Feature | Implementation |
|---|---|
| **Custom title bar with integrated tabs** | `WindowChrome` with 40px caption height; tab strip sits in the title bar alongside system caption buttons (min/max/restore/close) styled with Segoe Fluent Icons |
| **Mica backdrop** | DWM `DWMWA_SYSTEMBACKDROP_TYPE` applied on Windows 11 (build 22000+), tinting the window background with the desktop wallpaper color |
| **Dark title bar** | `DWMWA_USE_IMMERSIVE_DARK_MODE` to match the system theme |
| **Window corner radius** | `WindowChrome CornerRadius="8"` for rounded corners |
| **System tray icon** | `NotifyIcon` with context menu (New Tab, Open, Recent, Exit); double-click restores |
| **Jump list** | `JumpList` populated with the 10 most recent files for taskbar right-click |
| **Single instance** | Named mutex ensures only one instance runs; second launch activates the first |
| **Drag-and-drop** | Files dropped onto the editor open immediately |
| **Ctrl+Wheel zoom** | Mouse wheel while holding Ctrl increases/decreases font size |
| **Editor context menu** | Right-click in the editor for Cut/Copy/Paste/Select All/Find/Go To/Snippets |
| **DPI-aware** | `PerMonitorV2` DPI awareness via `ApplicationHighDpiMode` |
| **Segoe Fluent Icons** | All icons (close, search, arrows, file icons in tabs) use the Segoe Fluent Icons font |
| **Segoe UI chrome** | All chrome text uses Segoe UI; editor defaults to Cascadia Mono |

## Feature parity with macOS

| macOS (Swift/SwiftUI + NSTextView) | Windows (C#/WPF + RichTextBox) |
|---|---|
| New / Open / Save / Save As, Save All, Revert, Close (`⌘…`) | Same, `Ctrl`-based: `Ctrl+T/N`, `Ctrl+O`, `Ctrl+S`, `Shift+Ctrl+S`, `Alt+Ctrl+S`, `Ctrl+W` |
| Auto-save (5s default) + drafts in `~/Library/Application Support/NoteIt/Autosave` | Same, drafts in `%AppData%\NoteIt\Autosave` |
| Search & replace: case, regex, whole-word, wrap, match count, highlight-all, Replace/All | Same engine ported to `System.Text.RegularExpressions` (`Ctrl+F/H/G`, `Shift+Ctrl+G`) |
| Spellcheck toggle (`⌥⌘K`) | WPF native spellcheck (`Alt+Ctrl+K`) |
| Word wrap toggle (`⌥⌘L`) | Same (`Alt+Ctrl+L`) |
| Snippets: `trigger + Tab`, `{date}`/`{time}`, `⌘J` manager | Same (`Tab`, `Ctrl+J`) |
| Undo/Redo/Cut/Copy/Paste/Select All | Native RichTextBox commands |
| Go to line (`⌘L`), Quick open (`⌘P`), Recents | Same (`Ctrl+L`, `Ctrl+P`) |
| Plain-text only + per-doc Format checkbox gating Bold/Italic/Underline | Same (`Ctrl+B/I/U` gated) |
| Line numbers (`⇧⌘L`), font size `⌘+/-/0` | Same (`Shift+Ctrl+L`, `Ctrl++/-…/0`) |
| Dark mode System/Light/Dark (`⌥⌘D`) | Same, follows Windows theme (`Alt+Ctrl+D`) |
| Export PDF (`⇧⌘E`), Export Text, Print (`⇧⌘P`) | Same (zero-dependency PDF writer + `PrintDialog`) |
| Settings: font/size/wrap/lines/spell/autosave/tab width/appearance (`⌘,`) | Same (`Ctrl+,`) |
| Status bar: Ln/Col, words, lines, saved state, filename | Same |

## Layout

```
windows/
  NoteIt.sln
  build.ps1                    — dotnet build (+ -Run)
  NoteIt/
    NoteIt.csproj              — net9.0-windows, UseWPF + UseWindowsForms, no external deps
    app.manifest               — DPI awareness, Windows 10/11 compatibility
    GlobalUsings.cs            — using aliases to resolve WPF/WinForms name collisions
    App.xaml[.cs]              — shared DocumentStore singleton, theming, Mica backdrop
    Models.cs                  — EditorDocument, TextSnippet, AppSettings, SearchOptions
    DocumentStore.cs           — tabs, file IO, recents, autosave, find/replace, snippets
    PdfWriter.cs               — zero-dependency PDF 1.4 writer
    MainWindow.xaml[.cs]       — custom title bar + tabs, find bar, gutter + editor, status bar, menus
    Dialogs.cs                 — GoToLine / QuickOpen / Snippets / Settings windows
    WindowsIntegration.cs      — system tray, jump list, single-instance enforcement
```

## Build & run

Requires .NET 9 SDK on Windows 10/11.

```powershell
# from the repo root on the `windows` branch
.\windows\build.ps1            # Release build
.\windows\build.ps1 -Run       # build + launch
dotnet run --project windows\NoteIt -c Release -- file1.txt file2.txt
```

Settings/snippets/recents persist as JSON in `%AppData%\NoteIt\`
(`settings.json`, `snippets.json`, `recents.json`).

## Notes

- Saved files are plain-text UTF-8, exactly like macOS; Bold/Italic/Underline
  are view-level (gated by the per-doc **Format** checkbox) and not persisted.
- `Tab` first tries snippet-trigger expansion, otherwise inserts TabWidth spaces.
- Paste strips rich formatting while **Format** is off (plain-text only mode).
- Single-instance enforcement means launching a second copy activates the first
  and exits. Pass file paths as arguments to open them in the running instance.
