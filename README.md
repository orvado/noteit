# NoteIt — lightweight macOS text editor

Modern, fast, native macOS-only text editor. SwiftUI + `NSTextView`. Multiple documents in tabs, instant launch, minimal chrome.

## Features

- **New / Open / Save / Save As** (`⌘N` `⌘T` `⌘O` `⌘S` `⇧⌘S`), Save All (`⌥⌘S`), Revert, Close (`⌘W`)
- **Auto-save** (default 5s, toggle + interval in Settings; untitled drafts kept in `~/Library/Application Support/NoteIt/Autosave`)
- **Session restore**: relaunch reopens your tabs — files from disk, untitled tabs from drafts — with the last-selected tab selected
- **Sophisticated search & replace**: case-sensitive, regex (`.*`), whole-word, wrap-around, live match count, highlight-all, Replace / Replace All
- **Spellcheck** toggle (`⌥⌘K`, status bar “Spell”)
- **Word wrap** toggle (`⌥⌘L`, status bar “Wrap”), horizontal scroll when off
- **Snippets**: `trigger + Tab` to expand, `{date}`/`{time}` templates, `⌘J` manager + insert, defaults: `date time lorem sig todo swiftlet swiftfunc`
- **Language packs**: built-in snippet packs (~30 snippets each) for Python, JavaScript, Java, C#, C/C++, TypeScript, SQL, Go, Rust and Kotlin — include them via **Language Packs…** in the snippet manager; each pack shows as a folder whose snippets can be viewed, added, edited and deleted (edits persist even while a pack is turned off)
- **Active language**: detected per tab from the file extension, or from content for unsaved files; override it in the status-bar picker (the manual choice sticks until the tab closes) — only the active language's pack snippets expand
- **Syntax highlighting** for the 10 pack languages, with 9 color schemes (light + dark) configurable in Settings with a live preview; extensible per-language rule sets and theme catalog
- **Workspace & file explorer**: open a folder (`⌥⌘O`) and browse it in a collapsible sidebar (`⌘\`) — single click previews a file in a read-only tab, double click opens it for editing, unsaved files show green; the workspace is remembered between launches
- **Undo / Redo** (`⌘Z` `⇧⌘Z`), **Cut / Copy / Paste / Select All** (`⌘X C V A`) — native responder chain
- **Find next / previous** (`⌘G` `⇧⌘G`), native Find panel also available
- **Go to line** (`⌘L`)
- **Multiple tabs + multiple windows** (in-app tab bar + `⇧⌘N` new window + native tab bar)
- **Plain-text only** by default; per-doc “Format” checkbox (status bar) gates Bold (`⌘B`) / Italic (`⌘I`) / Underline (`⌘U`)
- **Line numbers** ruler (`⇧⌘L`), font size `⌘+` `⌘-` `⌘0`
- **Dark mode**: System / Light / Dark (`⌥⌘D` for dark), native vibrancy
- **Quick open** (`⌘P`) over recents + **Recent files** menu + `⌘O` browse
- **Export PDF** (`⇧⌘E`), Export Text, **Print** (`⇧⌘P`)
- **Minimal settings** (`⌘,`): font, size, wrap, line numbers, spell, plain-text, autosave, tab width, appearance
- **About dialog** (app menu → About NoteIt): feature overview, credits, full Apache 2.0 license text
- **In-app help** (`⌘?` / Help ▸ NoteIt Help): topic-by-topic usage guide for every feature
- **App icon**: macOS squircle with a folded-corner note card (`scripts/make-icon.sh` regenerates `Resources/NoteIt.icns`)
- Status bar: Ln/Col, words, lines, saved state, filename, language picker

## Run

Requires macOS 14+, Swift 5.10+ (CommandLineTools is enough — no full Xcode needed).

```sh
# dev (opens GUI)
swift run

# release .app bundle
./scripts/make-app.sh
open dist/NoteIt.app
```

With full Xcode installed you can also do `open Package.swift` — Xcode generates an `.xcodeproj` UI automatically.

## Layout

```
Sources/NoteIt/
  NoteItApp.swift    — @main App, WindowGroup, appearance
  Models.swift       — EditorDocument (incl. active language), TextSnippet, AppSettings, SearchOptions
  Language.swift     — Language packs: names, file extensions, content detection, sample code
  LanguagePackSnippets.swift — ~30 built-in snippets per language pack
  SyntaxHighlighting.swift — per-language tokenizer (keywords/strings/comments/…)
  HighlightThemes.swift — syntax color scheme catalog (9 themes)
  DocumentStore.swift— tabs, file IO, recents, autosave, find/replace engine, goto, snippets + language packs, export/print
  EditorView.swift   — NSTextView wrapper + line-number ruler, wrap, spell, tab width
  ContentView.swift  — tab bar, editor, status bar (+ language picker), toolbar + notification bridge
  Panels.swift       — SearchReplaceBar, GoToLine, QuickOpen (⌘P), Snippets manager + Language Packs, Settings
  AboutView.swift    — About dialog (features, credits, Apache 2.0 license)
  HelpView.swift     — in-app help browser (⌘?): detailed usage instructions per feature
  License.swift      — embedded Apache License 2.0 text (shown in About)
  WorkspaceExplorer.swift — workspace folder tree (preview vs. edit, unsaved markers)
  Commands.swift     — all menus + shortcuts, Format gating
Resources/Info.plist — app bundle metadata
Resources/NoteIt.icns— app icon (generated)
LICENSE              — Apache License 2.0
scripts/make-app.sh  — SwiftPM → NoteIt.app packager
scripts/make-icon.sh — icon render + icns packager (calls make-icon.swift)
```

## Shortcuts cheat sheet

| Action | Shortcut |
|---|---|
| New tab / window | `⌘T` / `⇧⌘N` |
| Open / Quick open | `⌘O` / `⌘P` |
| Open folder (workspace) | `⌥⌘O` |
| Toggle file explorer | `⌘\` |
| Save / As / All | `⌘S` / `⇧⌘S` / `⌥⌘S` |
| Find / Replace | `⌘F` / `⌥⌘F` |
| Next / Prev | `⌘G` / `⇧⌘G` |
| Go to line | `⌘L` |
| Snippets | `⌘J`, expand with `Tab` |
| Wrap / Lines / Spell | `⌥⌘L` / `⇧⌘L` / `⌥⌘K` |
| Font + / − / 0 | `⌘+` `⌘-` `⌘0` |
| Dark appearance | `⌥⌘D` |
| Export PDF / Print | `⇧⌘E` / `⇧⌘P` |
| Settings | `⌘,` |
| Help | `⌘?` |

## Notes

- Lightweight: no WebView/Electron, cold start ~instant, memory ~tens of MB.
- Plain-text UTF-8 throughout; formatting attributes are only kept when “Format” is on.
- Autosave writes through to the file URL when present, otherwise to drafts (restored on launch).

## License

Copyright 2026 Ken Richards (kenr@orvado.com). Licensed under the Apache License, Version 2.0 — see [LICENSE](LICENSE). The full license text is also available in-app via **NoteIt → About NoteIt → View License**.
