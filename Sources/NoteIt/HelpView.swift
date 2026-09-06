import SwiftUI

// MARK: - Help content model

/// One renderable block of help content.
enum HelpBlock {
    case text(String)
    case bullets([String])
    case steps([String])
    case shortcuts([(keys: String, action: String)])
    case note(String)
}

struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String
    let blocks: [HelpBlock]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Help topics

let helpTopics: [HelpTopic] = [
    HelpTopic(
        id: "start", title: "Getting Started", icon: "sparkles",
        subtitle: "The basics of the NoteIt window",
        blocks: [
            .text("NoteIt is a lightweight, native macOS text editor for notes and code. Everything lives in one window: a tab bar at the top, the editor in the middle, and a status bar at the bottom."),
            .bullets([
                "Press ⌘N or ⌘T for a new tab, or click the + at the right end of the tab bar. ⇧⌘N opens a whole new window.",
                "Start typing. The tab shows a “•” next to its title while it has unsaved changes.",
                "Save with ⌘S. Untitled documents are automatically kept as drafts, so your text survives a crash or relaunch.",
                "The status bar shows cursor position, word and line counts, the file name, and the active language.",
            ]),
        ]
    ),
    HelpTopic(
        id: "files", title: "Working with Files", icon: "folder",
        subtitle: "Opening, saving, and closing documents",
        blocks: [
            .text("There are three ways to open a file:"),
            .bullets([
                "⌘O — browse with the standard open panel (select several files to open them all).",
                "⌘P — Quick Open: type to filter your recent files, press ⏎ to open the top match.",
                "File ▸ Open Recent — the last 15 files you have opened.",
            ]),
            .note("If the file is already open in a tab, NoteIt simply switches to that tab and reloads the file from disk. Opening a file into an empty, untouched “Untitled” tab reuses that tab."),
            .text("Saving:"),
            .shortcuts([
                ("⌘S", "Save the current tab (asks for a name if it’s untitled)"),
                ("⇧⌘S", "Save As… — save a copy under a new name or location"),
                ("⌥⌘S", "Save All — write every tab with unsaved changes"),
                ("⇧⌘N", "New Window — all windows share the same tabs"),
            ]),
            .text("Closing: the × on each tab closes that document; ⌘W closes the window. Tabs with unsaved changes ask first — choose Save, Don’t Save, or Cancel. “Don’t Save” also discards the draft of an untitled tab."),
            .text("File ▸ Revert to Saved puts the tab back to the last version on disk."),
        ]
    ),
    HelpTopic(
        id: "editing", title: "Editing Text", icon: "square.and.pencil",
        subtitle: "Formatting, view options, and the status bar",
        blocks: [
            .text("Documents are plain text (UTF-8) by default — anything you paste keeps just its characters, no hidden formatting."),
            .bullets([
                "Bold (⌘B), Italic (⌘I) and Underline (⌘U) are available per document: tick “Format” in the status bar first. Formatting attributes live in that document only while it is open; saving stays plain text.",
                "Line numbers: ⇧⌘L toggles the gutter.",
                "Word wrap: ⌥⌘L (also the “Wrap” checkbox in the status bar). When off, long lines scroll horizontally.",
                "Spellcheck: ⌥⌘K (status bar “Spell”).",
                "Font size: ⌘+ bigger, ⌘- smaller, ⌘0 reset. The default font, size, and tab width live in Settings (⌘,).",
            ]),
            .note("The status bar always shows Ln/Col for the caret, word and line counts, saved/unsaved state, the file name, and the language picker."),
        ]
    ),
    HelpTopic(
        id: "find", title: "Find & Replace", icon: "magnifyingglass",
        subtitle: "Searching the current document",
        blocks: [
            .steps([
                "Press ⌘F. The find bar appears above the editor with focus in the search field.",
                "Type what to look for — matches are highlighted live and counted in the bar.",
                "Jump between matches with ⏎ / ⌘G (next) and ⇧⌘G (previous).",
                "Press Esc to close the bar, clear the highlights, and return to the editor.",
            ]),
            .text("Search options (buttons in the find bar):"),
            .bullets([
                "“Aa” — case-sensitive matching.",
                ".* — treat the query as a regular expression.",
                "W — whole words only.",
                "Wrap — continue from the top after the last match.",
            ]),
            .text("Replacing: press ⌥⌘F (or the ∨ button) to reveal the replace row. “Replace” swaps the current match and jumps to the next; “Replace All” rewrites every match in the document. In regex mode the replacement text is inserted literally."),
        ]
    ),
    HelpTopic(
        id: "navigate", title: "Navigating", icon: "arrow.right.circle",
        subtitle: "Go to Line and Quick Open",
        blocks: [
            .text("Go to Line (⌘L): opens a small sheet showing the document’s line range. Type a line number and press ⏎ — the caret lands on that line and it flashes into view."),
            .text("Quick Open (⌘P): a fast way back to recent files."),
            .bullets([
                "Type to filter the recents list by file name.",
                "⏎ opens the top match; click any row to open it.",
                "“Browse…” switches to the full open panel (⌘O).",
            ]),
        ]
    ),
    HelpTopic(
        id: "snippets", title: "Snippets", icon: "text.badge.plus",
        subtitle: "Triggers, Tab expansion, and placeholders",
        blocks: [
            .text("A snippet is a short trigger word that expands into longer text when you press Tab."),
            .steps([
                "In the editor, type a trigger — for example todo.",
                "Press Tab. The trigger is replaced by the snippet’s expansion.",
            ]),
            .text("Placeholders: expansions can contain <#placeholder#> tokens. The first one is selected right away so you can type straight over it. Keep pressing Tab to jump to the next token, ⇧Tab to go back, and Esc to finish placeholder editing early. After the last token, Tab goes back to its normal job (indenting)."),
            .note("The {date} and {time} templates are filled in with the current date and time at the moment of expansion."),
            .text("Managing snippets (⌘J, or the snippets button in the toolbar):"),
            .bullets([
                "+ adds a snippet; the ⧉ button duplicates the selected one; − or ⌫ deletes it (with confirmation).",
                "Edit the trigger, description, and expansion in the detail pane on the right. Warnings appear for empty triggers, spaces in triggers, duplicate triggers, or empty expansions.",
                "The Filter box searches triggers, descriptions, and expansions.",
                "Insert puts the selected snippet straight into the editor at the caret.",
                "Restore Defaults replaces your personal list with the built-in set (language packs are not affected).",
            ]),
        ]
    ),
    HelpTopic(
        id: "packs", title: "Language Packs", icon: "square.grid.2x2",
        subtitle: "Built-in snippet collections per language",
        blocks: [
            .text("Language packs bundle roughly 30 built-in snippets for each of the ten supported languages: Python, JavaScript, Java, C#, C/C++, TypeScript, SQL, Go, Rust, and Kotlin."),
            .steps([
                "Open the snippet manager with ⌘J.",
                "Click “Language Packs…” and tick the packs you want (the list scrolls).",
                "Back in the manager, each included pack appears as a folder. Click the folder to open it and browse its snippets.",
            ]),
            .text("Pack snippets are fully editable, just like your own:"),
            .bullets([
                "Select a snippet inside a folder and edit it in the detail pane — changes are saved immediately.",
                "+ adds to the pack you’re browsing (the folder’s context menu also has “New Snippet”).",
                "Delete or duplicate works per snippet; the folder’s context menu has “Reset to Built-ins…” to restore the original set.",
            ]),
            .note("Edits are permanent. Turning a pack off hides it but keeps your edited snippets — turning the pack back on later restores exactly what you left. “Restore Defaults” only ever touches “My Snippets”, never packs."),
        ]
    ),
    HelpTopic(
        id: "language", title: "Active Language", icon: "globe",
        subtitle: "Which pack is live in the editor",
        blocks: [
            .text("Only one language is active per tab. It decides which pack’s snippets expand on Tab — your personal snippets always work as well and win when a trigger exists in both places. That’s why the same trigger may safely exist in several packs."),
            .text("The active language is chosen automatically:"),
            .bullets([
                "Saved files — from the file extension (.py, .js, .java, .cs, .c/.cpp/.h, .ts, .sql, .go, .rs, .kt, …).",
                "Unsaved tabs — by analysing the content (imports, keywords, and other language fingerprints).",
                "If neither gives an answer the language is “Unknown” and no pack snippets are active.",
            ]),
            .text("Manual override: the language picker in the status bar lists all languages plus Unknown. Picking one switches the active pack immediately — and from then on automatic detection stays paused for that tab, even if you switch it to Unknown. Detection resumes in a new tab. The tooltip under the picker shows whether the language is detected or manually pinned."),
        ]
    ),
    HelpTopic(
        id: "autosave", title: "Auto-save & Drafts", icon: "clock.arrow.circlepath",
        subtitle: "Never lose an untitled note",
        blocks: [
            .text("Auto-save runs in the background every few seconds (Settings ⌘, — on by default, interval 2–60 s, 5 s standard)."),
            .bullets([
                "Tabs with a file on disk are written straight back to the file.",
                "Untitled tabs are stored as drafts in ~/Library/Application Support/NoteIt/Autosave and reopened as tabs the next time you launch NoteIt.",
                "Closing an untitled tab asks Save / Don’t Save / Cancel — “Don’t Save” removes its draft for good.",
            ]),
        ]
    ),
    HelpTopic(
        id: "export", title: "Export & Print", icon: "printer",
        subtitle: "PDF, plain text, and paper",
        blocks: [
            .shortcuts([
                ("⇧⌘E", "Export the current tab as a PDF"),
                ("⌥⌘E", "Export as Text (Save As with a .txt file name)"),
                ("⇧⌘P", "Print the current tab"),
            ]),
            .text("The PDF export renders the document with the editor’s current font, one page after another."),
        ]
    ),
    HelpTopic(
        id: "settings", title: "Settings", icon: "gearshape",
        subtitle: "App-wide preferences (⌘,)",
        blocks: [
            .bullets([
                "Appearance — System, Light, or Dark (⌥⌘D jumps straight to Dark).",
                "Font and size — the editor’s default typeface (SF Mono, Menlo, Helvetica, Courier).",
                "Wrap long lines, Show line numbers, Spellcheck.",
                "Plain-text only — strips formatting on paste; untick per document with the status bar “Format” checkbox.",
                "Auto-save on/off and its interval.",
                "Tab width (2–8 spaces).",
            ]),
        ]
    ),
    HelpTopic(
        id: "shortcuts", title: "Keyboard Shortcuts", icon: "keyboard",
        subtitle: "Every shortcut in one list",
        blocks: [
            .shortcuts([
                ("⌘N / ⌘T", "New document / new tab"),
                ("⇧⌘N", "New window"),
                ("⌘O / ⌘P", "Open… / Quick Open"),
                ("⌘W", "Close window"),
                ("⌘S / ⇧⌘S / ⌥⌘S", "Save / Save As… / Save All"),
                ("⌘F / ⌥⌘F", "Find / Find and Replace"),
                ("⌘G / ⇧⌘G", "Find next / previous"),
                ("⌘L", "Go to Line…"),
                ("⌘J", "Snippets manager"),
                ("Tab / ⇧Tab", "Expand trigger / move between snippet placeholders"),
                ("Esc", "End placeholder editing, or close the find bar"),
                ("⌥⌘L / ⇧⌘L / ⌥⌘K", "Word wrap / line numbers / spellcheck"),
                ("⌘B / ⌘I / ⌘U", "Bold / italic / underline (with “Format” on)"),
                ("⌘+ / ⌘- / ⌘0", "Bigger / smaller / reset font size"),
                ("⇧⌘E / ⌥⌘E / ⇧⌘P", "Export PDF / Export text / Print"),
                ("⌥⌘D", "Dark appearance"),
                ("⌘,", "Settings"),
                ("⌘?", "This help window"),
            ]),
        ]
    ),
]

// MARK: - Help dialog

/// Topic-browser help sheet: topic list on the left, detailed instructions
/// on the right.
struct HelpView: View {
    @Binding var isPresented: Bool
    @State private var selection: HelpTopic.ID = helpTopics.first?.id ?? ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                topicList
                Divider()
                detail
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack {
                Text("NoteIt Help")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 780, height: 580)
    }

    private var topicList: some View {
        List(selection: $selection) {
            ForEach(helpTopics) { topic in
                HStack(spacing: 8) {
                    Image(systemName: topic.icon)
                        .foregroundStyle(.tint)
                        .frame(width: 18)
                    Text(topic.title)
                }
                .tag(topic.id)
            }
        }
        .listStyle(.sidebar)
        .frame(width: 212)
    }

    private var selectedTopic: HelpTopic? {
        helpTopics.first(where: { $0.id == selection })
    }

    private var detail: some View {
        Group {
            if let topic = selectedTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: topic.icon)
                                .font(.title2)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(topic.title).font(.title2).fontWeight(.bold)
                                Text(topic.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.bottom, 4)

                        ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                            HelpBlockView(block: block)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Pick a topic").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Renders one help content block.
private struct HelpBlockView: View {
    let block: HelpBlock

    var body: some View {
        switch block {
        case .text(let s):
            Text(s).font(.callout).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items.indices, id: \.self) { i in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.tint)
                        Text(items[i]).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .steps(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.callout.weight(.medium)).foregroundStyle(.tint)
                            .frame(width: 18, alignment: .trailing)
                        Text(item).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .shortcuts(let rows):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        KbdKey(keys: row.keys)
                            .frame(width: 148, alignment: .leading)
                        Text(row.action).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 2)
        case .note(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                Text(s).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// A keyboard-cap style key label.
private struct KbdKey: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
