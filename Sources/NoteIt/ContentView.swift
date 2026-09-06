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
    /// Collapsible workspace pane; persisted so relaunches keep the choice.
    @AppStorage("NoteIt.explorerVisible") private var showExplorer = true
    /// Explorer pane width, drag-resizable and persisted.
    @AppStorage("NoteIt.explorerWidth") private var explorerWidth = 232.0
    /// Which view the left pane shows — like VSCode's Explorer/Search tabs.
    @AppStorage("NoteIt.paneMode") private var paneMode: PaneMode = .explorer

    enum PaneMode: String {
        case explorer, search
    }

    var body: some View {
        toolbarLayer
    }

    /// Layered view modifiers keep the type-checker happy — one long chain
    /// (sheets + notifications + toolbar) no longer compiles in reasonable
    /// time.
    private var toolbarLayer: some View {
        receiverLayer
            .focusedSceneValue(\.documentStore, store)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: { withAnimation { showExplorer.toggle() } }) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Toggle file explorer (⌘\\)")
                }
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

    private var receiverLayer: some View {
        sheetLayer
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
            .onReceive(NotificationCenter.default.publisher(for: .noteItOpenFolder)) { _ in
                store.openWorkspacePanel()
                showExplorer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteItCloseWorkspace)) { _ in
                store.closeWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteItToggleExplorer)) { _ in
                withAnimation { showExplorer.toggle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteItSearchWorkspace)) { _ in
                paneMode = .search
                showExplorer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteItFindNext)) { _ in store.findNext() }
            .onReceive(NotificationCenter.default.publisher(for: .noteItFindPrev)) { _ in store.findPrevious() }
            .onReceive(NotificationCenter.default.publisher(for: .noteItToggleWrap)) { _ in store.settings.wrapLines.toggle() }
            .onReceive(NotificationCenter.default.publisher(for: .noteItToggleSpell)) { _ in store.settings.spellcheck.toggle() }
    }

    private var sheetLayer: some View {
        HStack(spacing: 0) {
            if showExplorer {
                leftPane
                resizeHandle
            }
            mainColumn
        }
        .sheet(isPresented: $showGoTo) { GoToLineSheet(store: store, isPresented: $showGoTo) }
        .sheet(isPresented: $showQuickOpen) { QuickOpenSheet(store: store, isPresented: $showQuickOpen) }
        .sheet(isPresented: $showSnippets) { SnippetsSheet(store: store, isPresented: $showSnippets) }
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store, isPresented: $showSettings) }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showHelp) { HelpView(isPresented: $showHelp) }
    }

    // MARK: - Left pane (explorer / workspace search)
    private var leftPane: some View {
        VStack(spacing: 0) {
            Picker("Pane", selection: $paneMode) {
                Text("Files").tag(PaneMode.explorer)
                Text("Search").tag(PaneMode.search)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8).padding(.vertical, 6)
            switch paneMode {
            case .explorer:
                WorkspaceExplorer(store: store, workspace: store.workspace)
            case .search:
                WorkspaceSearchPane(store: store, search: store.workspaceSearch)
            }
        }
        .frame(width: explorerWidth)
    }

    private var mainColumn: some View {
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
        .frame(maxWidth: .infinity)
    }

    // MARK: - Explorer resize handle
    private var resizeHandle: some View {
        PaneSplitter(width: $explorerWidth, min: 160, max: 440)
            .frame(width: 8)
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
            if doc.isPreview { Text("Preview").foregroundStyle(.secondary) }
            else if doc.isDirty { Text("● Unsaved").foregroundStyle(.orange) }
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

    private var tabIcon: String {
        if doc.isPreview { return "eye" }
        return doc.fileURL == nil ? "doc" : "doc.text.fill"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tabIcon)
                .foregroundColor(isSelected ? .accentColor : .secondary).font(.caption)
            Text(doc.displayTitle).lineLimit(1).font(.callout).italic(doc.isPreview)
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

/// Native pane splitter for the explorer edge. SwiftUI's onHover/DragGesture
/// on a bare strip get overruled by the surrounding AppKit views (the
/// NSTextView editor wins cursor updates and can swallow the gesture), so
/// the divider is a real NSView with a proper cursor rect and mouse
/// tracking — the reliable macOS pattern for draggable pane dividers.
struct PaneSplitter: NSViewRepresentable {
    @Binding var width: Double
    var min: Double
    var max: Double

    func makeNSView(context: Context) -> SplitterView {
        let v = SplitterView()
        v.minWidth = min
        v.maxWidth = max
        v.currentWidth = width
        return v
    }

    func updateNSView(_ v: SplitterView, context: Context) {
        v.minWidth = min
        v.maxWidth = max
        v.currentWidth = width
        v.onResize = { width = $0 }
    }

    final class SplitterView: NSView {
        var minWidth: Double = 160
        var maxWidth: Double = 440
        var currentWidth: Double = 232
        var onResize: ((Double) -> Void)?
        private var startWindowX: CGFloat?
        private var startWidth: Double?

        override var acceptsFirstResponder: Bool { false }
        override var isOpaque: Bool { false }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: bounds.midX, y: 0))
            line.line(to: NSPoint(x: bounds.midX, y: bounds.height))
            line.lineWidth = 1
            line.stroke()
        }

        // Deltas are measured in window coordinates — the view's own origin
        // shifts on every step of the resize as SwiftUI re-lays out the pane.
        override func mouseDown(with event: NSEvent) {
            startWindowX = event.locationInWindow.x
            startWidth = currentWidth
            // Cursor rects are suspended for the whole drag session; hold the
            // resize cursor ourselves so it stays consistent.
            NSCursor.resizeLeftRight.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let x0 = startWindowX, let w0 = startWidth else { return }
            let dx = Double(event.locationInWindow.x - x0)
            onResize?(Swift.min(maxWidth, Swift.max(minWidth, w0 + dx)))
        }

        override func mouseUp(with event: NSEvent) {
            startWindowX = nil
            startWidth = nil
            // A drag session suspends cursor rects, so releasing the button
            // over a view without cursor management (the SwiftUI pane beside
            // us, after the pane clamped at its minimum) would leave the
            // resize cursor stuck. Restore the arrow and re-arm our rects —
            // if the pointer is still over the splitter, the resize cursor
            // correctly comes right back.
            NSCursor.arrow.set()
            window?.invalidateCursorRects(for: self)
        }
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
    static let noteItOpenFolder = Notification.Name("noteItOpenFolder")
    static let noteItCloseWorkspace = Notification.Name("noteItCloseWorkspace")
    static let noteItToggleExplorer = Notification.Name("noteItToggleExplorer")
    static let noteItSearchWorkspace = Notification.Name("noteItSearchWorkspace")
    static let noteItFindNext = Notification.Name("noteItFindNext")
    static let noteItFindPrev = Notification.Name("noteItFindPrev")
    static let noteItToggleWrap = Notification.Name("noteItToggleWrap")
    static let noteItToggleSpell = Notification.Name("noteItToggleSpell")
}
