import Foundation
import AppKit

// MARK: - EditorDocument
final class EditorDocument: ObservableObject, Identifiable, Equatable {
    static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool { lhs.id == rhs.id }

    let id = UUID()
    @Published var text: String {
        didSet {
            if text != oldValue {
                isDirty = true
                refreshLanguageDetection()
            }
        }
    }
    @Published var fileURL: URL? {
        didSet { refreshLanguageDetection() }
    }
    @Published var isDirty: Bool = false
    @Published var cursorLine: Int = 1
    @Published var cursorColumn: Int = 1
    /// When false the doc is plain-text only (no rich text / no formatting cmds).
    @Published var formattingEnabled: Bool = false
    /// Preview tabs (single click in the file explorer): read-only, never
    /// dirty, excluded from auto-save and session restore. Promoted to a
    /// normal tab on double click.
    @Published var isPreview: Bool

    init(text: String = "", fileURL: URL? = nil, isPreview: Bool = false) {
        self.text = text
        self.fileURL = fileURL
        self.isDirty = false
        self.isPreview = isPreview
        refreshLanguageDetection()
    }

    var title: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        return "Untitled"
    }

    var displayTitle: String { isDirty ? "\(title) •" : title }

    /// The document's active snippet-pack language, or nil for "Unknown".
    @Published private(set) var activeLanguage: Language?
    /// True once the user picked a language manually (status-bar picker).
    /// Auto-detection then stays off for the rest of this document's life —
    /// even if the user switches back to Unknown.
    private(set) var languagePinnedByUser: Bool = false

    /// Manual override from the status bar. Pinning survives save-as and
    /// content changes; only a fresh tab auto-detects again.
    func setActiveLanguage(_ lang: Language?) {
        activeLanguage = lang
        languagePinnedByUser = true
    }

    /// Re-runs auto-detection unless the user pinned a language: extension of
    /// the saved file first, then (unsaved docs only) content heuristics.
    func refreshLanguageDetection() {
        guard !languagePinnedByUser else { return }
        if let ext = fileURL?.pathExtension, !ext.isEmpty {
            activeLanguage = Language.fromFileExtension(ext)
        } else if fileURL == nil {
            activeLanguage = Language.detect(fromContent: text)
        } else {
            activeLanguage = nil
        }
    }

    var wordCount: Int {
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count
    }

    var lineCount: Int { text.isEmpty ? 1 : text.components(separatedBy: "\n").count }
}

// MARK: - TextSnippet
struct TextSnippet: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var trigger: String
    var expansion: String
    var description: String = ""

    static var defaults: [TextSnippet] {
        [
            TextSnippet(trigger: "date", expansion: "{date}", description: "Today's date"),
            TextSnippet(trigger: "time", expansion: "{time}", description: "Current time"),
            TextSnippet(trigger: "lorem", expansion: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", description: "Lorem ipsum"),
            TextSnippet(trigger: "sig", expansion: "— Sent from NoteIt", description: "Signature"),
            TextSnippet(trigger: "todo", expansion: "☐ TODO: ", description: "Todo item"),
            TextSnippet(trigger: "swiftlet", expansion: "let <#name#> = <#value#>", description: "Swift let"),
            TextSnippet(trigger: "swiftfunc", expansion: "func <#name#>(<#params#>) {\n    <#body#>\n}", description: "Swift func"),
        ]
    }

    func resolvedExpansion() -> String {
        let df = DateFormatter(); df.dateStyle = .medium
        let tf = DateFormatter(); tf.timeStyle = .short
        return expansion
            .replacingOccurrences(of: "{date}", with: df.string(from: Date()))
            .replacingOccurrences(of: "{time}", with: tf.string(from: Date()))
    }
}

// MARK: - AppSettings
struct AppSettings: Codable {
    var fontName: String = "SF Mono"
    var fontSize: Double = 13
    var wrapLines: Bool = true
    var showLineNumbers: Bool = true
    var spellcheck: Bool = true
    var autoSaveEnabled: Bool = true
    var autoSaveInterval: Double = 5
    var appearance: Appearance = .system
    var tabWidth: Int = 4
    /// Syntax theme id — "none" disables highlighting (HighlightThemeCatalog).
    var highlightTheme: String = HighlightThemeCatalog.noneID

    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark
    }

    // Decoding tolerates keys missing from older persisted versions —
    // otherwise one new field would discard every stored preference.
    enum CodingKeys: String, CodingKey {
        case fontName, fontSize, wrapLines, showLineNumbers, spellcheck
        case autoSaveEnabled, autoSaveInterval, appearance, tabWidth, highlightTheme
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? "SF Mono"
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        wrapLines = try c.decodeIfPresent(Bool.self, forKey: .wrapLines) ?? true
        showLineNumbers = try c.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
        spellcheck = try c.decodeIfPresent(Bool.self, forKey: .spellcheck) ?? true
        autoSaveEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSaveEnabled) ?? true
        autoSaveInterval = try c.decodeIfPresent(Double.self, forKey: .autoSaveInterval) ?? 5
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system
        tabWidth = try c.decodeIfPresent(Int.self, forKey: .tabWidth) ?? 4
        highlightTheme = try c.decodeIfPresent(String.self, forKey: .highlightTheme) ?? HighlightThemeCatalog.noneID
    }
}

// MARK: - SearchOptions
struct SearchOptions {
    var query: String = ""
    var replacement: String = ""
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
    var useRegex: Bool = false
    var wrapAround: Bool = true
}
