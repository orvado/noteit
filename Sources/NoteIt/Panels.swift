import SwiftUI
import AppKit

// MARK: - Search / Replace bar
struct SearchReplaceBar: View {
    @ObservedObject var store: DocumentStore
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
                Button(action: { store.search.query = ""; clearHighlight() }) {
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

// MARK: - Snippets manager + picker
struct SnippetsSheet: View {
    @ObservedObject var store: DocumentStore
    @Binding var isPresented: Bool
    @State private var newTrigger = ""
    @State private var newExpansion = ""

    var body: some View {
        VStack {
            Text("Text Snippets").font(.headline)
            Text("Type a trigger then press Tab to expand. {date} and {time} auto-fill.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(store.snippets) { s in
                    HStack {
                        Text(s.trigger).font(.system(.body, design: .monospaced)).frame(width: 100, alignment: .leading)
                        Text(s.resolvedExpansion()).lineLimit(2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Insert") { store.insertSnippet(s); isPresented = false }
                            .buttonStyle(.link)
                    }.contextMenu {
                        Button("Insert") { store.insertSnippet(s); isPresented = false }
                        Button("Delete", role: .destructive) {
                            store.snippets.removeAll { $0.id == s.id }
                        }
                    }
                }
                .onDelete { store.snippets.remove(atOffsets: $0) }
            }.frame(height: 220)
            HStack {
                TextField("trigger", text: $newTrigger).textFieldStyle(.roundedBorder).frame(width: 110)
                TextField("expansion…", text: $newExpansion).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let t = newTrigger.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !newExpansion.isEmpty else { return }
                    store.snippets.append(TextSnippet(trigger: t, expansion: newExpansion))
                    newTrigger = ""; newExpansion = ""
                }.disabled(newTrigger.isEmpty || newExpansion.isEmpty)
            }
            HStack { Spacer(); Button("Done") { isPresented = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(16).frame(width: 560)
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
