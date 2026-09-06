import SwiftUI
import AppKit
import Combine

// MARK: - Line number gutter
/// A plain NSView that draws line numbers to the left of the text view.
///
/// Why not `NSRulerView`: attaching a vertical ruler to the `NSScrollView`
/// makes AppKit reposition the clip view (and thus the document view) during
/// `tile()`. That left `NSTextView`'s private `NSViewBackingLayerContents`
/// content layer with stale geometry — the glyphs were rasterized off-screen,
/// so neither text nor the insertion point was painted, even though focus,
/// text storage, fonts and glyph layout were all perfectly correct.
///
/// A sibling view outside the scroll view never touches the scroll view's clip
/// geometry, so the text view keeps AppKit's normal, well-tested layout.
final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?

    var numberFont: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular) {
        didSet { if oldValue != numberFont { needsDisplay = true } }
    }
    var trailingPadding: CGFloat = 8
    var leadingPadding: CGFloat = 8
    /// Filled by the syntax theme; falls back to the system text background.
    var background: NSColor = .textBackgroundColor {
        didSet { if oldValue != background { needsDisplay = true } }
    }

    /// Top-down geometry, matching `NSTextView` (which is flipped).
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    private var digitWidth: CGFloat {
        ("8" as NSString).size(withAttributes: [.font: numberFont]).width
    }

    func width(forLineCount count: Int) -> CGFloat {
        let digits = max(2, String(max(1, count)).count)
        return ceil(digitWidth * CGFloat(digits)) + leadingPadding + trailingPadding
    }

    func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView,
              let layout = tv.layoutManager,
              let container = tv.textContainer else { return }

        background.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let origin = tv.textContainerOrigin
        let scrollY = tv.enclosingScrollView?.contentView.bounds.origin.y ?? 0

        // `y` is in gutter (flipped, top-down) coordinates.
        func draw(_ number: Int, lineTop lineY: CGFloat, lineHeight: CGFloat) {
            let s = "\(number)" as NSString
            let size = s.size(withAttributes: attrs)
            let y = lineY + origin.y - scrollY + (lineHeight - size.height) / 2
            guard y < dirtyRect.maxY + lineHeight,
                  y + size.height > dirtyRect.minY - lineHeight else { return }
            s.draw(at: NSPoint(x: bounds.width - trailingPadding - size.width, y: y),
                   withAttributes: attrs)
        }

        let ns = tv.string as NSString
        if ns.length == 0 {
            draw(1, lineTop: 0, lineHeight: layout.defaultLineHeight(for: tv.font ?? numberFont))
            return
        }

        let visible = tv.visibleRect
        guard visible.width > 0, visible.height > 0 else { return }
        // Convert the text view's visible rect into the text container's
        // coordinate space before asking the layout manager for glyphs.
        let query = NSRect(x: visible.minX - origin.x,
                           y: visible.minY - origin.y,
                           width: visible.width,
                           height: visible.height)
        let glyphRange = layout.glyphRange(forBoundingRect: query, in: container)
        guard glyphRange.location != NSNotFound, glyphRange.length > 0 else { return }

        // Line number of the first visible line.
        var number = 1
        if glyphRange.location > 0 {
            let cr = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if cr.location != NSNotFound, cr.location <= ns.length {
                number = ns.substring(to: cr.location).components(separatedBy: "\n").count
            }
        }

        var glyph = glyphRange.location
        var iterations = 0
        while glyph < NSMaxRange(glyphRange), iterations < 20_000 {
            iterations += 1
            guard glyph < layout.numberOfGlyphs else { break }
            var lineRange = NSRange(location: NSNotFound, length: 0)
            let rect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
            if lineRange.location == NSNotFound || lineRange.length == 0 { break }
            // Only the first fragment of a soft-wrapped line gets a number.
            if startsLine(glyph: glyph, layout: layout, text: ns) {
                draw(number, lineTop: rect.minY, lineHeight: rect.height)
                number += 1
            }
            let next = NSMaxRange(lineRange)
            if next <= glyph { break }
            glyph = next
        }
    }

    /// True when the glyph begins a logical line (i.e. the preceding character
    /// is a newline, or it is the first character in the document).
    private func startsLine(glyph: Int, layout: NSLayoutManager, text ns: NSString) -> Bool {
        let cr = layout.characterRange(forGlyphRange: NSRange(location: glyph, length: 1),
                                       actualGlyphRange: nil)
        if cr.location == 0 { return true }
        guard cr.location != NSNotFound, cr.location > 0, cr.location <= ns.length else { return false }
        return ns.substring(with: NSRange(location: cr.location - 1, length: 1)) == "\n"
    }
}

// MARK: - Editor container (gutter + scroll view)
/// Holds the gutter and the scroll view side by side and keeps the text view
/// sized so an empty document still fills the pane.
final class EditorContainerView: NSView {
    let gutter = LineNumberGutterView()
    let scroll = NSScrollView()
    let textView: NoteTextView

    var showsLineNumbers: Bool = true {
        didSet { if oldValue != showsLineNumbers { needsLayout = true; gutter.needsDisplay = true } }
    }
    var wrapLines: Bool = true {
        didSet { if oldValue != wrapLines { applyWrap() } }
    }

    private var gutterWidthValue: CGFloat = 44

    init(textView: NoteTextView) {
        self.textView = textView
        super.init(frame: .zero)
        gutter.textView = textView
        addSubview(gutter)
        addSubview(scroll)
        applyWrap()
        observe()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Sizing

    func applyWrap() {
        guard let tc = textView.textContainer else { return }
        if wrapLines {
            textView.isHorizontallyResizable = false
            tc.widthTracksTextView = true
            tc.heightTracksTextView = false
            tc.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.autoresizingMask = [.width]
            scroll.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            tc.widthTracksTextView = false
            tc.heightTracksTextView = false
            tc.containerSize = NSSize(width: 1e7, height: 1e7)
            textView.autoresizingMask = []
            scroll.hasHorizontalScroller = true
        }
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: 1e7, height: CGFloat.greatestFiniteMagnitude)
        needsLayout = true
        gutter.needsDisplay = true
    }

    override func layout() {
        super.layout()

        let g = showsLineNumbers ? gutterWidthValue : 0
        gutter.isHidden = !showsLineNumbers
        if showsLineNumbers {
            gutter.frame = NSRect(x: 0, y: 0, width: g, height: bounds.height)
        }
        let width = max(0, bounds.width - g)
        scroll.frame = NSRect(x: g, y: 0, width: width, height: bounds.height)

        let contentW = max(0, scroll.contentSize.width)
        let contentH = max(0, scroll.contentSize.height)

        // `minSize` is what NSTextView's own auto-resize clamps to, so this is
        // what makes a short document still cover the whole pane.
        let minW: CGFloat = wrapLines ? 0 : contentW
        if abs(textView.minSize.width - minW) > 0.5 || abs(textView.minSize.height - contentH) > 0.5 {
            textView.minSize = NSSize(width: minW, height: contentH)
        }

        // Belt and braces: make sure the frame actually covers the visible area.
        var frame = textView.frame
        if frame.height < contentH - 0.5 { frame.size.height = contentH }
        if !wrapLines, frame.width < contentW - 0.5 { frame.size.width = contentW }
        if abs(textView.frame.width - frame.width) > 0.5 || abs(textView.frame.height - frame.height) > 0.5 {
            textView.setFrameSize(frame.size)
        }

        // NSTextView rasterizes its drawn text into an internal layer whose
        // contents are keyed to the current visible rect. When the clip view's
        // frame changes (e.g. toggling the gutter, window resize), that cache
        // becomes stale and the text view paints nothing until something
        // nudges setFrameSize. Grow then restore the height to force the
        // content layer to redraw — without this, hiding/showing the gutter
        // turns the editor pane blank.
        let h = textView.frame.height
        textView.setFrameSize(NSSize(width: textView.frame.width, height: h + 1))
        textView.setFrameSize(NSSize(width: textView.frame.width, height: h))

        gutter.needsDisplay = true
    }

    func updateGutterWidth() {
        guard showsLineNumbers else { return }
        let count = (textView.string as NSString).components(separatedBy: "\n").count
        let w = ceil(gutter.width(forLineCount: count))
        if abs(gutterWidthValue - w) > 0.5 {
            gutterWidthValue = w
            needsLayout = true
        }
    }

    // MARK: Invalidation

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textDidChange(_:)),
                       name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(invalidateGutter(_:)),
                       name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        nc.addObserver(self, selector: #selector(invalidateGutter(_:)),
                       name: NSView.frameDidChangeNotification, object: scroll.contentView)
    }

    @objc private func textDidChange(_ note: Notification) {
        updateGutterWidth()
        gutter.needsDisplay = true
    }

    @objc private func invalidateGutter(_ note: Notification) {
        gutter.needsDisplay = true
    }
}

// MARK: - NSTextView subclass (Tab expands snippets, tracks cursor)
final class NoteTextView: NSTextView {
    var onTextChange: ((String) -> Void)?
    var onSelectionChange: ((Int, Int) -> Void)?
    var expandTrigger: (() -> Bool)?
    /// `backwards` is Shift-Tab. Returns false when there is no token to move
    /// to, so the key press falls through to Tab's normal behaviour (indent).
    var navigatePlaceholder: ((Bool) -> Bool)?
    /// Esc abandons an active placeholder session; false when none was active.
    var endPlaceholderSession: (() -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func didChangeText() {
        super.didChangeText()
        onTextChange?(string)
        updateCursor()
    }

    func updateCursor() {
        let sel = selectedRange()
        guard sel.location != NSNotFound else { return }
        let ns = string as NSString
        let upto = ns.substring(to: min(sel.location, ns.length))
        let lines = upto.components(separatedBy: "\n")
        let line = lines.count
        let col = (lines.last?.count ?? 0) + 1
        onSelectionChange?(line, col)
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: stillSelecting)
        updateCursor()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 { // Tab
            let backwards = event.modifierFlags.contains(.shift)
            // Forward Tab tries trigger expansion first — it bails out on a
            // non-empty selection, so a selected token is never re-expanded.
            // Shift-Tab is purely placeholder navigation.
            if !backwards, expandTrigger?() == true { return }
            if navigatePlaceholder?(backwards) == true { return }
        } else if event.keyCode == 53 { // Esc
            if endPlaceholderSession?() == true { return }
        }
        super.keyDown(with: event)
    }
}

// MARK: - SwiftUI wrapper
struct EditorView: NSViewRepresentable {
    @ObservedObject var document: EditorDocument
    @ObservedObject var store: DocumentStore

    func makeNSView(context: Context) -> EditorContainerView {
        let textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: 1e7, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator

        let container = EditorContainerView(textView: textView)
        let scroll = container.scroll
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = textView

        container.showsLineNumbers = store.settings.showLineNumbers
        container.wrapLines = store.settings.wrapLines

        applySettings(to: textView, container: container, force: true)
        textView.string = document.text
        context.coordinator.lastSyncedText = document.text
        context.coordinator.lastAppliedSettings = settingsFingerprint(store.settings)
        context.coordinator.textView = textView
        context.coordinator.docID = document.id
        // Character edits drive syntax re-highlighting.
        textView.textStorage?.delegate = context.coordinator

        store.registerTextView(textView, for: document.id)

        container.layoutSubtreeIfNeeded()
        container.updateGutterWidth()
        container.needsLayout = true

        // Auto-focus once the view is in a window.
        DispatchQueue.main.async { [weak textView] in
            guard let tv = textView else { return }
            if let window = tv.window {
                window.makeFirstResponder(tv)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak textView] in
                    guard let tv = textView, let window = tv.window else { return }
                    window.makeFirstResponder(tv)
                }
            }
        }

        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        let textView = container.textView

        if store.textViews[document.id] !== textView {
            store.registerTextView(textView, for: document.id)
        }
        context.coordinator.document = document
        context.coordinator.docID = document.id
        context.coordinator.store = store
        context.coordinator.textView = textView
        // Theme/language changes re-render SwiftUI, landing here — compare
        // against what's applied and re-highlight when they differ. Text
        // edits go through the storage delegate instead.
        context.coordinator.noteAppearance(theme: store.settings.highlightTheme)

        textView.onTextChange = { [weak document] newText in
            let doc = document ?? self.document
            if doc.text != newText { doc.text = newText }
        }
        textView.onSelectionChange = { [weak document] line, col in
            let doc = document ?? self.document
            if doc.cursorLine != line { doc.cursorLine = line }
            if doc.cursorColumn != col { doc.cursorColumn = col }
        }
        textView.expandTrigger = { [weak textView] in
            guard let tv = textView else { return false }
            return store.expandTriggerIfNeeded(in: tv)
        }
        textView.navigatePlaceholder = { [weak textView] backwards in
            guard let tv = textView else { return false }
            return store.navigatePlaceholder(in: tv, backwards: backwards)
        }
        textView.endPlaceholderSession = { store.endPlaceholderSession() }

        if container.showsLineNumbers != store.settings.showLineNumbers {
            container.showsLineNumbers = store.settings.showLineNumbers
            container.layoutSubtreeIfNeeded()
        }

        // Programmatic text change (open / revert / replace-all / etc.):
        // sync only when the model diverged from what we last pushed. While the
        // user types, onTextChange keeps document.text in sync with the text
        // view, so the two are equal and we skip here.
        if textView.string != document.text,
           context.coordinator.lastSyncedText != document.text {
            let sel = textView.selectedRange()
            textView.string = document.text
            context.coordinator.lastSyncedText = document.text
            let maxLoc = (textView.string as NSString).length
            if sel.location != NSNotFound {
                textView.setSelectedRange(NSRange(location: min(sel.location, maxLoc), length: 0))
            }
            container.updateGutterWidth()
            container.gutter.needsDisplay = true
        }

        let fp = settingsFingerprint(store.settings)
        if fp != context.coordinator.lastAppliedSettings {
            applySettings(to: textView, container: container, force: false)
            context.coordinator.lastAppliedSettings = fp
        }
    }

    static func dismantleNSView(_ container: EditorContainerView, coordinator: Coordinator) {
        coordinator.textView?.textStorage?.delegate = nil
        if let id = coordinator.docID {
            coordinator.store?.unregisterTextView(for: id)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(document: document, store: store)
    }

    private func settingsFingerprint(_ s: AppSettings) -> String {
        "\(s.fontName)|\(s.fontSize)|\(s.wrapLines)|\(s.showLineNumbers)|\(s.spellcheck)|\(s.tabWidth)"
    }

    private func applySettings(to textView: NoteTextView, container: EditorContainerView, force: Bool) {
        let s = store.settings
        let font: NSFont = {
            if let f = NSFont(name: s.fontName, size: s.fontSize) { return f }
            if s.fontName == "SF Mono" { return .monospacedSystemFont(ofSize: s.fontSize, weight: .regular) }
            return .systemFont(ofSize: s.fontSize)
        }()
        if force || textView.font?.fontName != font.fontName || textView.font?.pointSize != font.pointSize {
            textView.font = font
        }
        container.gutter.numberFont = .monospacedSystemFont(
            ofSize: min(max(s.fontSize - 1, 9), 12), weight: .regular)

        if container.wrapLines != s.wrapLines {
            container.wrapLines = s.wrapLines
        } else if force {
            container.applyWrap()
        }

        if textView.isContinuousSpellCheckingEnabled != s.spellcheck {
            textView.isContinuousSpellCheckingEnabled = s.spellcheck
        }
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isRichText = false
        textView.importsGraphics = false

        let tabW = CGFloat(s.tabWidth) * font.pointSize * 0.6
        let para = NSMutableParagraphStyle()
        para.tabStops = (1...16).map { NSTextTab(textAlignment: .left, location: CGFloat($0) * tabW, options: [:]) }
        para.defaultTabInterval = tabW
        textView.defaultParagraphStyle = para

        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        container.gutter.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        weak var textView: NoteTextView?
        weak var container: EditorContainerView?
        var docID: UUID?
        weak var store: DocumentStore?
        var document: EditorDocument
        var lastSyncedText: String = ""
        var lastAppliedSettings: String = ""
        private var rehighlightScheduled = false
        /// Current syntax theme id, plus what has been applied — compared on
        /// every SwiftUI pass so theme/language changes re-highlight.
        private var themeID: String = HighlightThemeCatalog.noneID
        private var appliedThemeID: String?
        private var appliedLanguage: Language?

        init(document: EditorDocument, store: DocumentStore) {
            self.document = document
            self.docID = document.id
            self.store = store
            self.lastSyncedText = document.text
        }

        // MARK: Syntax highlighting

        /// Called from updateNSView on every SwiftUI pass. Skips work unless
        /// the theme or the document's active language changed.
        func noteAppearance(theme: String) {
            let lang = document.activeLanguage
            guard appliedThemeID != theme || appliedLanguage != lang else { return }
            themeID = theme
            appliedThemeID = theme
            appliedLanguage = lang
            scheduleRehighlight()
        }

        /// Coalesces bursts of changes (each keystroke) into one pass.
        func scheduleRehighlight() {
            guard !rehighlightScheduled else { return }
            rehighlightScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.rehighlightScheduled = false
                self.rehighlight()
            }
        }

        /// Applies the syntax theme: background + plain color always (when a
        /// theme is selected), token colors for the document's active
        /// language. Only touches `.foregroundColor` and the background —
        /// font attributes and the undo stack are left alone.
        func rehighlight() {
            guard let textView else { return }
            let theme = HighlightThemeCatalog.resolve(themeID)

            let background = theme?.background ?? .textBackgroundColor
            textView.backgroundColor = background
            textView.enclosingScrollView?.backgroundColor = background
            container?.gutter.background = background
            textView.textColor = theme?.plain ?? .textColor

            guard let storage = textView.textStorage else { return }
            let whole = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            if let theme {
                storage.addAttribute(.foregroundColor, value: theme.plain, range: whole)
                if let lang = document.activeLanguage {
                    let text = storage.string
                    for token in SyntaxHighlighter.tokens(for: lang, text: text) {
                        storage.addAttribute(.foregroundColor,
                                             value: theme.color(for: token.type),
                                             range: token.range)
                    }
                }
            } else {
                storage.removeAttribute(.foregroundColor, range: whole)
            }
            storage.endEditing()
        }

        // MARK: NSTextStorageDelegate

        /// Character edits (typing, paste, replace-all, undo) re-highlight.
        /// Attribute-only edits (our own color pass) are ignored, which also
        /// breaks the would-be recursion.
        func textStorage(_ textStorage: NSTextStorage,
                         didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            scheduleRehighlight()
        }
    }
}
