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

/// Where a snippet lives: the personal list ("My Snippets") or one of the
/// enabled language packs. Duplicate triggers across scopes are fine — only
/// one language is ever active in the editor at a time.
enum SnippetSelection: Hashable {
    case global(TextSnippet.ID)
    case pack(Language, TextSnippet.ID)
}

struct SnippetsSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool

    @State private var selection: SnippetSelection?
    @State private var filter = ""
    @State private var pendingDelete: SnippetSelection?
    @State private var showRestoreConfirm = false
    @State private var showLanguagePacks = false
    @State private var expandedPacks: Set<Language> = []
    @State private var pendingPackReset: Language?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listPane.frame(width: 262)
                Divider()
                detailPane
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .onAppear { if selection == nil { selection = initialSelection } }
        // Delete key removes the selected snippet (confirmed first).
        .onDeleteCommand { if let sel = selection { pendingDelete = sel } }
        .sheet(isPresented: $showLanguagePacks) {
            LanguagePacksSheet(store: store, isPresented: $showLanguagePacks)
        }
        .alert("Delete Snippet?", isPresented: deleteAlert, presenting: pendingDelete) { sel in
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) { delete(sel); pendingDelete = nil }
        } message: { sel in
            Text("“\(trigger(of: sel))” will be removed. This can’t be undone.")
        }
        .alert("Restore Default Snippets?", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) { restoreDefaults() }
        } message: {
            Text("Your personal snippet list will be replaced by the built-in set. Language packs are not affected.")
        }
        .alert("Reset Pack to Built-ins?", isPresented: packResetAlert, presenting: pendingPackReset) { lang in
            Button("Cancel", role: .cancel) { pendingPackReset = nil }
            Button("Reset", role: .destructive) {
                store.setSnippets(lang.builtInSnippets, for: lang)
                pendingPackReset = nil
            }
        } message: { lang in
            Text("All snippets in the \(lang.displayName) pack — including your edits — will be replaced by the \(lang.builtInSnippets.count) built-in snippets.")
        }
    }

    // MARK: Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Text Snippets").font(.headline)
                Text("Type a trigger then press Tab to expand. {date} and {time} auto-fill.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Language Packs…") { showLanguagePacks = true }
                .help("Choose which programming-language snippet packs to include")
        }
        .padding(.top, 14).padding(.bottom, 10).padding(.horizontal, 16)
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Button(action: add) { Image(systemName: "plus") }
                    .help("New snippet (in the selected list)")
                Button(action: { if let sel = selection { pendingDelete = sel } }) { Image(systemName: "minus") }
                    .help("Delete snippet (⌫)").disabled(selection == nil)
                Button(action: duplicate) { Image(systemName: "square.on.square") }
                    .help("Duplicate snippet").disabled(selection == nil)
                Spacer()
                Text("\(totalSnippetCount)").font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8).padding(.vertical, 6)

            Divider()

            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8).padding(.vertical, 6)

            List(selection: $selection) {
                Section("My Snippets") {
                    ForEach(filteredGlobal) { snip in
                        snippetRow(snip, sel: .global(snip.id))
                    }
                }
                if !store.enabledLanguages.isEmpty {
                    Section("Language Packs") {
                        ForEach(orderedEnabledPacks) { lang in
                            packGroup(for: lang)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func snippetRow(_ snip: TextSnippet, sel: SnippetSelection) -> some View {
        SnippetRow(snippet: snip, flagged: !isUsable(snip, peers: peers(of: sel)))
            .tag(sel)
            .contextMenu {
                Button("Insert") { insert(snip) }
                Button("Duplicate") { selection = sel; duplicate() }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = sel }
            }
    }

    /// A pack folder: expandable, with its snippets inside. While a filter is
    /// active the folder stays open and hides entirely when nothing matches.
    @ViewBuilder
    private func packGroup(for lang: Language) -> some View {
        let matches = filteredPack(lang)
        if filter.isEmpty || !matches.isEmpty {
            DisclosureGroup(isExpanded: packExpansion(for: lang)) {
                ForEach(matches) { snip in
                    snippetRow(snip, sel: .pack(lang, snip.id))
                }
                if matches.isEmpty && filter.isEmpty {
                    Text("No snippets")
                        .font(.caption).italic().foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(.tint).font(.callout)
                    Text(lang.displayName)
                    Text("(\(store.snippets(for: lang).count))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .contextMenu {
                    Button("New Snippet") { add(to: lang) }
                    Divider()
                    Button("Reset to Built-ins…") { pendingPackReset = lang }
                }
            }
        }
    }

    private var detailPane: some View {
        Group {
            if let ctx = selection.flatMap(editorContext) {
                editor(ctx)
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

    private func editor(_ c: SnippetEditorContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pack = c.packName {
                Label(pack, systemImage: "folder.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Trigger") {
                TextField("e.g. sig", text: c.snippet.trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            LabeledContent("Description") {
                TextField("optional", text: c.snippet.description)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Expansion").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: c.snippet.expansion)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            }

            if let problem = validation(for: c.snippet.wrappedValue, peers: c.peers) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Preview — {date} / {time} resolved")
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    Text(c.snippet.wrappedValue.resolvedExpansion())
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
                .help("Replace your personal snippets with the built-in set")
            Spacer()
            if let ctx = selection.flatMap(editorContext) {
                Button("Insert") { insert(ctx.snippet.wrappedValue) }
                    .disabled(validation(for: ctx.snippet.wrappedValue, peers: ctx.peers) != nil)
                    .help("Insert this snippet at the cursor and close")
            }
            Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    // MARK: Data

    private struct SnippetEditorContext {
        let snippet: Binding<TextSnippet>
        let peers: [TextSnippet]
        let packName: String?
    }

    /// Binding into the snippet's containing list (personal or pack). The
    /// bindings are rebuilt every render, so they always point at the
    /// current index after inserts/deletes.
    private func editorContext(_ sel: SnippetSelection) -> SnippetEditorContext? {
        switch sel {
        case .global(let id):
            guard let idx = store.snippets.firstIndex(where: { $0.id == id }) else { return nil }
            return SnippetEditorContext(
                snippet: Binding(
                    get: { self.store.snippets.indices.contains(idx) ? self.store.snippets[idx] : TextSnippet(trigger: "", expansion: "") },
                    set: { if self.store.snippets.indices.contains(idx) { self.store.snippets[idx] = $0 } }),
                peers: store.snippets,
                packName: nil)
        case .pack(let lang, let id):
            let list = store.snippets(for: lang)
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return nil }
            return SnippetEditorContext(
                snippet: Binding(
                    get: { self.store.snippets(for: lang).indices.contains(idx) ? self.store.snippets(for: lang)[idx] : TextSnippet(trigger: "", expansion: "") },
                    set: {
                        var l = self.store.snippets(for: lang)
                        guard l.indices.contains(idx) else { return }
                        l[idx] = $0
                        self.store.setSnippets(l, for: lang)
                    }),
                peers: list,
                packName: lang.displayName)
        }
    }

    private var filterQuery: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func matches(_ s: TextSnippet) -> Bool {
        let q = filterQuery
        guard !q.isEmpty else { return true }
        return s.trigger.lowercased().contains(q)
            || s.description.lowercased().contains(q)
            || s.expansion.lowercased().contains(q)
    }

    private var filteredGlobal: [TextSnippet] {
        store.snippets.filter(matches)
    }

    /// Enabled packs in "most popular language" order (the enum's case order).
    private var orderedEnabledPacks: [Language] {
        Language.allCases.filter { store.enabledLanguages.contains($0) }
    }

    private func filteredPack(_ lang: Language) -> [TextSnippet] {
        if !filterQuery.isEmpty, lang.displayName.lowercased().contains(filterQuery) {
            return store.snippets(for: lang)
        }
        return store.snippets(for: lang).filter(matches)
    }

    private var totalSnippetCount: Int {
        store.snippets.count + orderedEnabledPacks.reduce(0) { $0 + store.snippets(for: $1).count }
    }

    private var initialSelection: SnippetSelection? {
        if let first = store.snippets.first { return .global(first.id) }
        for lang in orderedEnabledPacks {
            if let first = store.snippets(for: lang).first { return .pack(lang, first.id) }
        }
        return nil
    }

    private func peers(of sel: SnippetSelection) -> [TextSnippet] {
        switch sel {
        case .global: return store.snippets
        case .pack(let lang, _): return store.snippets(for: lang)
        }
    }

    private func packExpansion(for lang: Language) -> Binding<Bool> {
        Binding(
            get: { !filterQuery.isEmpty || expandedPacks.contains(lang) },
            set: { open in
                // While filtering, folders are forced open so matches show.
                guard filterQuery.isEmpty else { return }
                if open { expandedPacks.insert(lang) } else { expandedPacks.remove(lang) }
            }
        )
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var packResetAlert: Binding<Bool> {
        Binding(get: { pendingPackReset != nil }, set: { if !$0 { pendingPackReset = nil } })
    }

    private func trigger(of sel: SnippetSelection) -> String {
        switch sel {
        case .global(let id):
            return store.snippets.first(where: { $0.id == id })?.trigger ?? ""
        case .pack(let lang, let id):
            return store.snippets(for: lang).first(where: { $0.id == id })?.trigger ?? ""
        }
    }

    /// A snippet is usable when it has a unique, whitespace-free trigger and a
    /// non-empty expansion. Uniqueness only counts within its own list — the
    /// same trigger may exist in other packs or in My Snippets.
    private func isUsable(_ s: TextSnippet, peers: [TextSnippet]) -> Bool {
        validation(for: s, peers: peers) == nil
    }

    private func validation(for s: TextSnippet, peers: [TextSnippet]) -> String? {
        let t = s.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "A trigger is required — it’s the word you type before pressing Tab." }
        if t.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return "Triggers can’t contain spaces or newlines."
        }
        if peers.contains(where: { $0.id != s.id && $0.trigger == t }) {
            return "“\(t)” is already used by another snippet in this list."
        }
        if s.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "The expansion is empty — this snippet would insert nothing."
        }
        return nil
    }

    // MARK: Actions

    /// + button: adds to the selected pack when a pack snippet is selected,
    /// otherwise to My Snippets.
    private func add() {
        if case .pack(let lang, _) = selection {
            add(to: lang)
        } else {
            let s = TextSnippet(trigger: uniqueTrigger(from: "new", in: store.snippets), expansion: "", description: "")
            store.snippets.append(s)
            selection = .global(s.id)
            filter = ""
        }
    }

    private func add(to lang: Language) {
        let list = store.snippets(for: lang)
        let s = TextSnippet(trigger: uniqueTrigger(from: "new", in: list), expansion: "", description: "")
        store.setSnippets(list + [s], for: lang)
        expandedPacks.insert(lang)
        selection = .pack(lang, s.id)
        filter = ""
    }

    private func duplicate() {
        guard let sel = selection else { return }
        switch sel {
        case .global(let id):
            guard let idx = store.snippets.firstIndex(where: { $0.id == id }) else { return }
            var copy = store.snippets[idx]
            copy.id = UUID()
            copy.trigger = uniqueTrigger(from: copy.trigger, in: store.snippets)
            store.snippets.insert(copy, at: idx + 1)
            selection = .global(copy.id)
        case .pack(let lang, let id):
            var list = store.snippets(for: lang)
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            var copy = list[idx]
            copy.id = UUID()
            copy.trigger = uniqueTrigger(from: copy.trigger, in: list)
            list.insert(copy, at: idx + 1)
            store.setSnippets(list, for: lang)
            expandedPacks.insert(lang)
            selection = .pack(lang, copy.id)
        }
        filter = ""
    }

    private func delete(_ sel: SnippetSelection) {
        switch sel {
        case .global(let id):
            guard let idx = store.snippets.firstIndex(where: { $0.id == id }) else { return }
            store.snippets.remove(at: idx)
            if selection == sel {
                if store.snippets.indices.contains(idx) {
                    selection = .global(store.snippets[idx].id)
                } else if store.snippets.indices.contains(idx - 1) {
                    selection = .global(store.snippets[idx - 1].id)
                } else {
                    selection = initialSelection
                }
            }
        case .pack(let lang, let id):
            var list = store.snippets(for: lang)
            guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
            list.remove(at: idx)
            store.setSnippets(list, for: lang)
            if selection == sel {
                if list.indices.contains(idx) {
                    selection = .pack(lang, list[idx].id)
                } else if list.indices.contains(idx - 1) {
                    selection = .pack(lang, list[idx - 1].id)
                } else {
                    selection = nil
                }
            }
        }
    }

    private func insert(_ s: TextSnippet) {
        store.insertSnippet(s)
        isPresented = false
    }

    private func restoreDefaults() {
        store.snippets = TextSnippet.defaults
        selection = store.snippets.first.map { .global($0.id) }
        filter = ""
    }

    /// Appends 2, 3, … to `base` until the trigger isn't already taken in
    /// the given list.
    private func uniqueTrigger(from base: String, in peers: [TextSnippet]) -> String {
        let taken = Set(peers.map { $0.trigger })
        var candidate = base
        var n = 2
        while taken.contains(candidate) { candidate = "\(base)\(n)"; n += 1 }
        return candidate
    }
}

// MARK: - Language pack picker
/// Scrollable checkbox list of the built-in language packs. Toggling a pack
/// on seeds its snippet copy (first time only); toggling off keeps the
/// edited copy so re-enabling restores the user's snippets.
struct LanguagePacksSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Language Packs").font(.headline)
                Text("Included packs appear as folders in the snippet manager. A pack’s snippets become active when a document of that language is open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Language.allCases) { lang in
                        Toggle(isOn: packBinding(lang)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lang.displayName)
                                    Text("\(lang.builtInSnippets.count) built-in snippets")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(maxHeight: 264)
            Text("Edits made inside a pack are kept even while the pack is turned off — turning it back on restores your edited snippets.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func packBinding(_ lang: Language) -> Binding<Bool> {
        Binding(
            get: { store.enabledLanguages.contains(lang) },
            set: { store.setLanguagePack(lang, enabled: $0) }
        )
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
            Divider()
            syntaxThemeSection
            HStack { Spacer(); Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(20).frame(width: 440)
    }

    private var syntaxThemeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Syntax colors", selection: $store.settings.highlightTheme) {
                    Text("None").tag(HighlightThemeCatalog.noneID)
                    ForEach(HighlightThemeCatalog.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Spacer()
            }
            SyntaxThemePreview(
                themeID: store.settings.highlightTheme,
                language: previewLanguage)
                .frame(height: 168)
            Text("Live preview — the open tab's language (\(previewLanguage.displayName)); the editor re-colors instantly.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var previewLanguage: Language {
        store.selectedDocument?.activeLanguage ?? .python
    }
}

// MARK: - Syntax theme preview

/// Renders sample code through the real tokenizer with the selected theme's
/// colors, on the theme's background — a faithful miniature of the editor.
struct SyntaxThemePreview: View {
    let themeID: String
    let language: Language

    var body: some View {
        let theme = HighlightThemeCatalog.resolve(themeID)
        let background = theme.map { Color(nsColor: $0.background) } ?? Color(nsColor: .textBackgroundColor)
        let attributed = attributedSample(theme: theme)

        return ScrollView([.horizontal]) {
            Text(attributed)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }

    private func attributedSample(theme: HighlightTheme?) -> AttributedString {
        let plainColor = theme?.plain ?? NSColor.textColor
        let code = language.sampleCode
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: plainColor,
            ])
        let ns = code as NSString
        for token in SyntaxHighlighter.tokens(for: language, text: code) {
            guard token.range.location + token.range.length <= ns.length else { continue }
            let color = theme.map { $0.color(for: token.type) } ?? NSColor.textColor
            attributed.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        return AttributedString(attributed)
    }
}
