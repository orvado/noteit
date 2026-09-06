import SwiftUI
import AppKit

struct NoteItCommands: Commands {
    // Fallback for when no window is focused (e.g. all closed).
    // NOTE: DocumentStore is a class — this reference always points at the
    // live app store, so menu actions can never hit a stale copy.
    @ObservedObject var appStore: DocumentStore
    @FocusedValue(\.documentStore) var focusedStore: DocumentStore?
    @Environment(\.openWindow) private var openWindow

    /// The front window's store when available, else the app store.
    private var store: DocumentStore { focusedStore ?? appStore }

    var body: some Commands {
        // MARK: - File
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { store.newDocument() }.keyboardShortcut("t", modifiers: .command)
            Button("New Document") { store.newDocument() }.keyboardShortcut("n", modifiers: .command)
            Button("New Window") {
                // Opens another WindowGroup(id: "main") window. All windows
                // share the app store (single source of truth for tabs).
                openWindow(id: "main")
            }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open…") { store.open() }.keyboardShortcut("o", modifiers: .command)
            Button("Open Folder…") {
                NotificationCenter.default.post(name: .noteItOpenFolder, object: nil)
            }.keyboardShortcut("o", modifiers: [.command, .option])
            Button("Close Workspace") {
                NotificationCenter.default.post(name: .noteItCloseWorkspace, object: nil)
            }.disabled(!store.workspace.isOpen)
            Button("Quick Open…") {
                NotificationCenter.default.post(name: .noteItQuickOpen, object: nil)
            }.keyboardShortcut("p", modifiers: .command)
            Menu("Open Recent") {
                if store.recentFiles.isEmpty {
                    Text("No Recent Files").foregroundStyle(.secondary)
                } else {
                    ForEach(store.recentFiles.prefix(10), id: \.self) { url in
                        Button(url.lastPathComponent) { store.open(url: url) }
                    }
                    Divider()
                    Button("Clear Menu") { store.recentFiles = [] }
                }
            }
        }

        CommandGroup(after: .newItem) {
            Button("Save") { store.selectedDocument.map { store.save($0) } }
                .keyboardShortcut("s", modifiers: .command)
            Button("Save As…") { store.selectedDocument.map { store.save($0, saveAs: true) } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Save All") { store.saveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Button("Revert to Saved") { store.selectedDocument.map { store.revert($0) } }
            Divider()
            Button("Export as PDF…") { store.selectedDocument.map { store.exportPDF($0) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export as Text…") { store.selectedDocument.map { store.exportText($0) } }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button("Print…") { store.selectedDocument.map { store.printDocument($0) } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // MARK: - Edit / Find
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { NotificationCenter.default.post(name: .noteItToggleFind, object: nil) }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find and Replace…") { NotificationCenter.default.post(name: .noteItToggleReplace, object: nil) }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find in Workspace…") {
                NotificationCenter.default.post(name: .noteItSearchWorkspace, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Find Next") { store.findNext() }.keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { store.findPrevious() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Go to Line…") { NotificationCenter.default.post(name: .noteItGoToLine, object: nil) }
                .keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("Toggle Word Wrap") { store.settings.wrapLines.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Toggle Line Numbers") { store.settings.showLineNumbers.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Toggle Spellcheck") { store.settings.spellcheck.toggle() }
                .keyboardShortcut("k", modifiers: [.command, .option])
            Divider()
            Button("Insert Snippet…") { NotificationCenter.default.post(name: .noteItSnippets, object: nil) }
                .keyboardShortcut("j", modifiers: .command)
            Button("Manage Snippets…") { NotificationCenter.default.post(name: .noteItSnippets, object: nil) }
        }

        // MARK: - Format (off by default, plain-text only)
        CommandMenu("Format") {
            Button("Bold") { toggleTrait(.boldFontMask) }.keyboardShortcut("b", modifiers: .command)
            Button("Italic") { toggleTrait(.italicFontMask) }.keyboardShortcut("i", modifiers: .command)
            Button("Underline") { toggleUnderline() }.keyboardShortcut("u", modifiers: .command)
            Divider()
            Text("Formatting is OFF by default (plain-text). Enable per-document via status bar “Format” checkbox.")
                .foregroundStyle(.secondary)
        }

        // MARK: - View
        CommandGroup(after: .toolbar) {
            Button("Toggle File Explorer") {
                NotificationCenter.default.post(name: .noteItToggleExplorer, object: nil)
            }.keyboardShortcut("\\", modifiers: .command)
            Divider()
            Button("Appearance: System") { store.settings.appearance = .system }
            Button("Appearance: Light") { store.settings.appearance = .light }
            Button("Appearance: Dark") { store.settings.appearance = .dark }
                .keyboardShortcut("d", modifiers: [.command, .option])
            Divider()
            Button("Increase Font Size") { store.settings.fontSize = min(28, store.settings.fontSize + 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size") { store.settings.fontSize = max(9, store.settings.fontSize - 1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { store.settings.fontSize = 13 }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button("About NoteIt") {
                NotificationCenter.default.post(name: .noteItAbout, object: nil)
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { NotificationCenter.default.post(name: .noteItSettings, object: nil) }
                .keyboardShortcut(",", modifiers: .command)
        }

        // MARK: - Help
        CommandGroup(replacing: .help) {
            Button("NoteIt Help") {
                NotificationCenter.default.post(name: .noteItHelp, object: nil)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    // MARK: - Formatting helpers (only when doc.formattingEnabled)
    private func toggleTrait(_ mask: NSFontTraitMask) {
        guard let doc = store.selectedDocument,
              let tv = store.textViews[doc.id] else { return }
        guard doc.formattingEnabled else {
            NSSound.beep()
            let a = NSAlert()
            a.messageText = "Plain-text only mode"
            a.informativeText = "Enable “Format” in the status bar to use Bold / Italic."
            a.runModal()
            return
        }
        tv.toggleTrait(mask)
    }

    private func toggleUnderline() {
        guard let doc = store.selectedDocument,
              let tv = store.textViews[doc.id] else { return }
        guard doc.formattingEnabled else { NSSound.beep(); return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        let attrs = tv.textStorage?.attributes(at: sel.location, effectiveRange: nil) ?? [:]
        let has = (attrs[.underlineStyle] as? Int ?? 0) != 0
        tv.textStorage?.addAttribute(.underlineStyle, value: has ? 0 : NSUnderlineStyle.single.rawValue, range: sel)
        tv.didChangeText()
        store.syncFromTextView(tv, to: doc)
    }
}

extension NSTextView {
    func toggleTrait(_ mask: NSFontTraitMask) {
        let sel = selectedRange()
        guard layoutManager != nil, textContainer != nil else { return }
        let range: NSRange = sel.length > 0 ? sel : NSRange(location: sel.location, length: 0)
        let fm = NSFontManager.shared
        if range.length > 0 {
            textStorage?.enumerateAttribute(.font, in: range) { value, r, _ in
                let base = (value as? NSFont) ?? self.font ?? NSFont.systemFont(ofSize: 13)
                if fm.traits(of: base).contains(mask) {
                    let converted = fm.convert(base, toNotHaveTrait: mask)
                    textStorage?.addAttribute(.font, value: converted, range: r)
                } else {
                    let converted = fm.convert(base, toHaveTrait: mask)
                    textStorage?.addAttribute(.font, value: converted, range: r)
                }
            }
            didChangeText()
        } else {
            let base = font ?? NSFont.systemFont(ofSize: 13)
            if fm.traits(of: base).contains(mask) {
                font = fm.convert(base, toNotHaveTrait: mask)
            } else {
                font = fm.convert(base, toHaveTrait: mask)
            }
        }
    }
}
