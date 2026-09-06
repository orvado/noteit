import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: DocumentStore
    @State private var showFind = false
    @State private var showReplace = false
    @State private var showGoTo = false
    @State private var showQuickOpen = false
    @State private var showSnippets = false
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            if showFind || showReplace {
                SearchReplaceBar(store: store, showFind: $showFind, showReplace: $showReplace)
                Divider()
            }
            editorArea
            Divider()
            if let doc = store.selectedDocument {
                StatusBarView(doc: doc, store: store)
            } else {
                HStack { Text("No documents").font(.caption).foregroundStyle(.secondary); Spacer() }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.bar)
            }
        }
        .sheet(isPresented: $showGoTo) { GoToLineSheet(store: store, isPresented: $showGoTo) }
        .sheet(isPresented: $showQuickOpen) { QuickOpenSheet(store: store, isPresented: $showQuickOpen) }
        .sheet(isPresented: $showSnippets) { SnippetsSheet(store: store, isPresented: $showSnippets) }
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store, isPresented: $showSettings) }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showHelp) { HelpView(isPresented: $showHelp) }
        .onReceive(NotificationCenter.default.publisher(for: .noteItToggleFind)) { _ in
            showReplace = false; showFind.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteItToggleReplace)) { _ in
            showFind = true; showReplace.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .noteItGoToLine)) { _ in showGoTo = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItQuickOpen)) { _ in showQuickOpen = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItSnippets)) { _ in showSnippets = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItSettings)) { _ in showSettings = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItAbout)) { _ in showAbout = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItHelp)) { _ in showHelp = true }
        .onReceive(NotificationCenter.default.publisher(for: .noteItFindNext)) { _ in store.findNext() }
        .onReceive(NotificationCenter.default.publisher(for: .noteItFindPrev)) { _ in store.findPrevious() }
        .onReceive(NotificationCenter.default.publisher(for: .noteItToggleWrap)) { _ in store.settings.wrapLines.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .noteItToggleSpell)) { _ in store.settings.spellcheck.toggle() }
        .focusedSceneValue(\.documentStore, store)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { store.selectedDocument.map { store.save($0) } }) {
                    Image(systemName: "square.and.arrow.down")
                }.help("Save (⌘S)")
                Button(action: { showQuickOpen = true }) {
                    Image(systemName: "magnifyingglass")
                }.help("Quick open (⌘P)")
                Button(action: { showFind = true; showReplace = false }) {
                    Image(systemName: "text.magnifyingglass")
                }.help("Find (⌘F)")
                Button(action: { showSnippets = true }) {
                    Image(systemName: "text.badge.plus")
                }.help("Snippets (⌘J)")
            }
        }
    }

    // MARK: - Tab bar
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(store.documents) { doc in
                    TabChip(doc: doc, isSelected: store.selectedID == doc.id, store: store)
                        .onTapGesture { store.select(doc) }
                }
                Button(action: { store.newDocument() }) {
                    Image(systemName: "plus").frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .help("New tab (⌘T / ⌘N)")
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var editorArea: some View {
        if let doc = store.selectedDocument {
            EditorView(document: doc, store: store)
                .id(doc.id) // keep text view per tab; state preserved via store.textViews + doc.text
                // FIX: NSViewRepresentable has no intrinsic size — without this
                // the scroll view collapses to zero height in the VStack,
                // producing a blank pane with no cursor that can't be typed in.
                .frame(minWidth: 200, maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                .layoutPriority(1)
        } else {
            Text("No documents").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StatusBarView: View {
    @ObservedObject var doc: EditorDocument
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 12) {
            Text("Ln \(doc.cursorLine), Col \(doc.cursorColumn)")
            Text("\(doc.wordCount) words")
            Text("\(doc.lineCount) lines")
            if doc.isDirty { Text("● Unsaved").foregroundStyle(.orange) }
            else { Text("Saved").foregroundStyle(.secondary) }
            if let url = doc.fileURL {
                Text(url.lastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(url.path)
            }
            languagePicker
            Spacer()
            Toggle(isOn: $store.settings.wrapLines) { Text("Wrap") }
                .toggleStyle(.checkbox).font(.caption).help("Wrap long lines (⌥⌘L)")
            Toggle(isOn: $store.settings.spellcheck) { Text("Spell") }
                .toggleStyle(.checkbox).font(.caption).help("Spellcheck (⌥⌘S)")
            Toggle(isOn: Binding(get: { doc.formattingEnabled }, set: { doc.formattingEnabled = $0 })) { Text("Format") }
                .toggleStyle(.checkbox).font(.caption)
                .help("Basic formatting (bold/italic) — off by default, plain-text only when off")
            Text(store.settings.fontName).font(.caption).foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.bar)
    }

    /// Manual language override. Picking anything here (including Unknown)
    /// pins the choice: auto-detection stays off until the tab is closed.
    private var languagePicker: some View {
        Picker("Language", selection: Binding(
            get: { doc.activeLanguage },
            set: { doc.setActiveLanguage($0) }
        )) {
            Text("Unknown").tag(Language?.none)
            ForEach(Language.allCases) { lang in
                Text(lang.displayName).tag(Language?.some(lang))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help(doc.languagePinnedByUser
              ? "Language set manually — auto-detection is paused for this tab"
              : "Active language, detected from the file extension or content. Choose one to override.")
    }
}

struct TabChip: View {
    @ObservedObject var doc: EditorDocument
    var isSelected: Bool
    @ObservedObject var store: DocumentStore
    @State private var hoveringClose = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: doc.fileURL == nil ? "doc" : "doc.text.fill")
                .foregroundColor(isSelected ? .accentColor : .secondary).font(.caption)
            Text(doc.displayTitle).lineLimit(1).font(.callout)
            closeButton
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1))
        .cornerRadius(7)
        .frame(maxWidth: 200)
    }

    /// The "xmark" glyph at .caption2 is only ~8pt square, which makes it a
    /// fiddly target. Pad it out to a full 18x18 rectangle and use
    /// .contentShape(Rectangle()) so the *entire* rectangle is hit-testable,
    /// not just the drawn glyph. The glyph stays small; only the target grows.
    /// 18pt matches the chip's text line height, so the tab bar grows ~1pt.
    private var closeButton: some View {
        Button(action: { store.closeDocument(doc) }) {
            Image(systemName: "xmark")
                .font(.caption2)
                .foregroundStyle(hoveringClose ? .primary : .secondary)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hoveringClose ? Color.primary.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveringClose = $0 }
        .help("Close tab (⌘W)")
    }
}

struct DocumentStoreFocusedKey: FocusedValueKey {
    typealias Value = DocumentStore
}

extension FocusedValues {
    var documentStore: DocumentStore? {
        get { self[DocumentStoreFocusedKey.self] }
        set { self[DocumentStoreFocusedKey.self] = newValue }
    }
}

extension Notification.Name {    static let noteItToggleFind = Notification.Name("noteItToggleFind")
    static let noteItToggleReplace = Notification.Name("noteItToggleReplace")
    static let noteItGoToLine = Notification.Name("noteItGoToLine")
    static let noteItQuickOpen = Notification.Name("noteItQuickOpen")
    static let noteItSnippets = Notification.Name("noteItSnippets")
    static let noteItSettings = Notification.Name("noteItSettings")
    static let noteItAbout = Notification.Name("noteItAbout")
    static let noteItHelp = Notification.Name("noteItHelp")
    static let noteItFindNext = Notification.Name("noteItFindNext")
    static let noteItFindPrev = Notification.Name("noteItFindPrev")
    static let noteItToggleWrap = Notification.Name("noteItToggleWrap")
    static let noteItToggleSpell = Notification.Name("noteItToggleSpell")
}
