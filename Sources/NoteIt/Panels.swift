import SwiftUI
import AppKit

// MARK: - Search / Replace bar
struct SearchReplaceBar: View {
    @ObservedObject var store: DocumentStore
    @Binding var showFind: Bool
    @Binding var showReplace: Bool
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find", text: $store.search.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($focused)
                    .onSubmit { store.findNext() }
                Button(store.search.caseSensitive ? "Aa" : "Aa") {
                    store.search.caseSensitive.toggle(); highlightAll()
                }
                .buttonStyle(.bordered)
                .tint(store.search.caseSensitive ? .accentColor : .secondary)
                    .help("Case sensitive (⌥⌘C)")
                Button(".*") { store.search.useRegex.toggle() }
                    .buttonStyle(.bordered).tint(store.search.useRegex ? .accentColor : .secondary)
                    .help("Regular expression (⌥⌘R)")
                Button("W") { store.search.wholeWord.toggle() }
                    .buttonStyle(.bordered).tint(store.search.wholeWord ? .accentColor : .secondary)
                    .help("Whole word (⌥⌘W)")
                Button(action: { store.findPrevious() }) { Image(systemName: "chevron.up") }
                    .help("Find previous (⇧⌘G)")
                Button(action: { store.findNext() }) { Image(systemName: "chevron.down") }
                    .help("Find next (⌘G)")
                Button(action: { withAnimation { showReplace.toggle() } }) {
                    Image(systemName: showReplace ? "chevron.up.square" : "chevron.down.square")
                }.help("Toggle replace (⌥⌘F)")
                if let doc = store.selectedDocument, !store.search.query.isEmpty {
                    let n = store.ranges(of: store.search.query, in: doc.text).count
                    Text("\(n) match\(n == 1 ? "" : "es")")
                        .font(.caption).foregroundStyle(.secondary).frame(minWidth: 70, alignment: .leading)
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Close (Esc)")
            }
            if showReplace {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                    TextField("Replace", text: $store.search.replacement)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                        .onSubmit { store.replaceCurrent() }
                    Button("Replace") { store.replaceCurrent() }.help("Replace current (⌘⌥E)")
                    Button("Replace All") { store.replaceAll() }.help("Replace all (⇧⌘⌥E)")
                    Toggle("Wrap", isOn: $store.search.wrapAround).font(.caption)
                    Spacer()
                }
            }
        }
        .padding(8)
        .background(.bar)
        .onChange(of: store.search.query) { highlightAll() }
        .onAppear { focused = true }
        // The button's help text promises Esc; make it actually work.
        .onExitCommand(perform: close)
    }

    /// Dismiss the whole bar (find + replace), drop the search highlights and
    /// hand focus back to the editor so the user can keep typing.
    private func close() {
        store.search.query = ""
        clearHighlight()
        showFind = false
        showReplace = false
        DispatchQueue.main.async { refocusEditor() }
    }

    private func refocusEditor() {
        guard let doc = store.selectedDocument, let tv = store.textViews[doc.id] else { return }
        tv.window?.makeFirstResponder(tv)
    }

    private func highlightAll() {
        guard let doc = store.selectedDocument, let tv = store.textViews[doc.id] else { return }
        tv.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (doc.text as NSString).length))
        guard !store.search.query.isEmpty else { return }
        let ranges = store.ranges(of: store.search.query, in: doc.text).prefix(500)
        for r in ranges {
            tv.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35), forCharacterRange: r)
        }
    }

    private func clearHighlight() {
        guard let doc = store.selectedDocument, let tv = store.textViews[doc.id] else { return }
        tv.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: (doc.text as NSString).length))
    }
}

// MARK: - Go to line sheet
struct GoToLineSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var lineText = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Go to Line").font(.headline)
            if let doc = store.selectedDocument {
                Text("1 … \(doc.lineCount)").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Line number", text: $lineText)
                .textFieldStyle(.roundedBorder).frame(width: 180)
                .onSubmit(go)
            HStack {
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Go") { go() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 260)
        .onAppear { lineText = store.selectedDocument.map { "\($0.cursorLine)" } ?? "" }
    }

    private func go() {
        if let n = Int(lineText.trimmingCharacters(in: .whitespaces)) {
            store.goToLine(n)
        }
        isPresented = false
    }
}

// MARK: - Quick open (Cmd+P)
struct QuickOpenSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var filter = ""
    @State private var selection: URL?

    var candidates: [URL] {
        let q = filter.lowercased()
        let base = store.recentFiles
        if q.isEmpty { return Array(base.prefix(10)) }
        return base.filter { $0.lastPathComponent.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 8) {
            TextField("Quick open…  (type to filter recents, ⏎ to open, ⌘O for browse)", text: $filter)
                .textFieldStyle(.roundedBorder)
                .onSubmit { openFirst() }
            List(candidates, id: \.self, selection: $selection) { url in
                HStack {
                    Image(systemName: "doc.text")
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent).lineLimit(1)
                        Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.tag(url as URL?)
            }
            .frame(height: 220)
            HStack {
                Button("Browse…") { isPresented = false; store.open() }
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Open") { openSelected() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 520)
    }

    private func openFirst() {
        if let first = candidates.first { store.open(url: first); isPresented = false }
    }
    private func openSelected() {
        if let s = selection { store.open(url: s) }
        isPresented = false
    }
}

// MARK: - Snippets manager
struct SnippetsSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool

    @State private var selection: TextSnippet.ID?
    @State private var filter = ""
    @State private var pendingDelete: TextSnippet.ID?
    @State private var showRestoreConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listPane.frame(width: 252)
                Divider()
                detailPane
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 720, height: 520)
        .onAppear { if selection == nil { selection = store.snippets.first?.id } }
        // Delete key removes the selected snippet (confirmed first).
        .onDeleteCommand { if let id = selection { pendingDelete = id } }
        .alert("Delete Snippet?", isPresented: deleteAlert, presenting: pendingDelete) { id in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { delete(id: id); pendingDelete = nil }
        } message: { id in
            Text("“\(trigger(of: id))” will be removed. This can’t be undone.")
        }
        .alert("Restore Default Snippets?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) { restoreDefaults() }
        } message: {
            Text("Every snippet in the list will be replaced by the built-in set.")
        }
    }

    // MARK: Subviews

    private var header: some View {
        VStack(spacing: 3) {
            Text("Text Snippets").font(.headline)
            Text("Type a trigger then press Tab to expand. {date} and {time} auto-fill.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 14).padding(.bottom, 10)
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Button(action: add) { Image(systemName: "plus") }
                    .help("New snippet")
                Button(action: { if let id = selection { pendingDelete = id } }) { Image(systemName: "minus") }
                    .help("Delete snippet (⌫)").disabled(selection == nil)
                Button(action: duplicate) { Image(systemName: "square.on.square") }
                    .help("Duplicate snippet").disabled(selection == nil)
                Spacer()
                Text("\(store.snippets.count)").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8).padding(.vertical, 6)

            Divider()

            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8).padding(.vertical, 6)

            List(filtered, selection: $selection) { snip in
                SnippetRow(snippet: snip, flagged: !isUsable(snip))
                    .tag(snip.id)
                    .contextMenu {
                        Button("Insert") { insert(snip) }
                        Button("Duplicate") { selection = snip.id; duplicate() }
                        Divider()
                        Button("Delete", role: .destructive) { pendingDelete = snip.id }
                    }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var detailPane: some View {
        Group {
            if let idx = selectedIndex, store.snippets.indices.contains(idx) {
                editor(for: idx)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No snippet selected").foregroundStyle(.secondary)
                    Text("Pick one on the left, or click + to add a new one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func editor(for idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Trigger") {
                TextField("e.g. sig", text: $store.snippets[idx].trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Description") {
                TextField("optional", text: $store.snippets[idx].description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Expansion").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $store.snippets[idx].expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            }

            if let problem = validation(for: store.snippets[idx]) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview — {date} / {time} resolved")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    Text(store.snippets[idx].resolvedExpansion())
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 56, maxHeight: 80)
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            Button("Restore Defaults") { showRestoreConfirm = true }
                .help("Replace the whole list with the built-in snippets")
            Spacer()
            if let idx = selectedIndex, store.snippets.indices.contains(idx) {
                Button("Insert") { insert(store.snippets[idx]) }
                    .disabled(validation(for: store.snippets[idx]) != nil)
                    .help("Insert this snippet at the cursor and close")
            }
            Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Data

    private var filtered: [TextSnippet] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.snippets }
        return store.snippets.filter {
            $0.trigger.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
                || $0.expansion.lowercased().contains(q)
        }
    }

    private var selectedIndex: Int? {
        guard let id = selection else { return nil }
        return store.snippets.firstIndex(where: { $0.id == id })
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private func trigger(of id: TextSnippet.ID) -> String {
        store.snippets.first(where: { $0.id == id })?.trigger ?? ""
    }

    /// A snippet is usable when it has a unique, whitespace-free trigger and a
    /// non-empty expansion. Anything else is flagged with a warning badge.
    private func isUsable(_ s: TextSnippet) -> Bool {
        validation(for: s) == nil
    }

    private func validation(for s: TextSnippet) -> String? {
        let t = s.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "A trigger is required — it’s the word you type before pressing Tab." }
        if t.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return "Triggers can’t contain spaces or newlines."
        }
        if store.snippets.contains(where: { $0.id != s.id && $0.trigger == t }) {
            return "“\(t)” is already used by another snippet."
        }
        if s.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The expansion is empty — this snippet would insert nothing."
        }
        return nil
    }

    // MARK: Actions

    private func add() {
        let s = TextSnippet(trigger: uniqueTrigger(from: "new"), expansion: "", description: "")
        store.snippets.append(s)
        selection = s.id
        filter = ""
    }

    private func duplicate() {
        guard let idx = selectedIndex else { return }
        var copy = store.snippets[idx]
        copy.id = UUID()
        copy.trigger = uniqueTrigger(from: copy.trigger)
        store.snippets.insert(copy, at: idx + 1)
        selection = copy.id
        filter = ""
    }

    private func delete(id: TextSnippet.ID) {
        guard let idx = store.snippets.firstIndex(where: { $0.id == id }) else { return }
        store.snippets.remove(at: idx)
        if selection == id {
            if store.snippets.indices.contains(idx) {
                selection = store.snippets[idx].id
            } else {
                selection = store.snippets.last?.id
            }
        }
    }

    private func insert(_ s: TextSnippet) {
        store.insertSnippet(s)
        isPresented = false
    }

    private func restoreDefaults() {
        store.snippets = TextSnippet.defaults
        selection = store.snippets.first?.id
        filter = ""
    }

    /// Appends 2, 3, … to `base` until the trigger isn't already taken.
    private func uniqueTrigger(from base: String) -> String {
        let taken = Set(store.snippets.map { $0.trigger })
        var candidate = base
        var n = 2
        while taken.contains(candidate) { candidate = "\(base)\(n)"; n += 1 }
        return candidate
    }
}

private struct SnippetRow: View {
    let snippet: TextSnippet
    var flagged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(snippet.trigger.isEmpty ? "—" : snippet.trigger)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(snippet.trigger.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if flagged {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .help("This snippet needs attention")
                }
            }
            if !snippet.description.isEmpty {
                Text(snippet.description)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Settings (minimal)
struct SettingsSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.headline)
            Picker("Appearance", selection: $store.settings.appearance) {
                ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Picker("Font", selection: $store.settings.fontName) {
                    Text("SF Mono").tag("SF Mono")
                    Text("Menlo").tag("Menlo")
                    Text("Helvetica").tag("Helvetica")
                    Text("Courier").tag("Courier")
                }.frame(width: 200)
                Stepper("Size \(Int(store.settings.fontSize))", value: $store.settings.fontSize, in: 9...28)
            }
            Toggle("Wrap long lines  (⌥⌘L)", isOn: $store.settings.wrapLines)
            Toggle("Show line numbers", isOn: $store.settings.showLineNumbers)
            Toggle("Spellcheck  (⌥⌘S)", isOn: $store.settings.spellcheck)
            Toggle("Plain-text only (strip formatting on paste)", isOn: Binding(
                get: { !(store.selectedDocument?.formattingEnabled ?? false) },
                set: { store.selectedDocument?.formattingEnabled = !$0 }
            )).help("Off by default for formatting; documents stay plain text")
            Toggle("Auto-save", isOn: $store.settings.autoSaveEnabled)
            if store.settings.autoSaveEnabled {
                HStack {
                    Slider(value: $store.settings.autoSaveInterval, in: 2...60, step: 1) { Text("Every") }
                    Text("\(Int(store.settings.autoSaveInterval))s").frame(width: 36)
                }.onChange(of: store.settings.autoSaveInterval) { store.startAutosave() }
            }
            Stepper("Tab width: \(store.settings.tabWidth)", value: $store.settings.tabWidth, in: 2...8)
            HStack { Spacer(); Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 420)
    }
}
