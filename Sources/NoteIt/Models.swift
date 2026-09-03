import Foundation
import AppKit

// MARK: - EditorDocument
final class EditorDocument: ObservableObject, Identifiable, Equatable {
    static func == (lhs: EditorDocument, rhs: EditorDocument) -> Bool { lhs.id == rhs.id }

    let id = UUID()
    @Published var text: String {
        didSet { if text != oldValue { isDirty = true } }
    }
    @Published var fileURL: URL?
    @Published var isDirty: Bool = false
    @Published var cursorLine: Int = 1
    @Published var cursorColumn: Int = 1
    /// When false the doc is plain-text only (no rich text / no formatting cmds).
    @Published var formattingEnabled: Bool = false

    init(text: String = "", fileURL: URL? = nil) {
        self.text = text
        self.fileURL = fileURL
        self.isDirty = false
    }

    var title: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        return "Untitled"
    }

    var displayTitle: String { isDirty ? "\(title) •" : title }

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

    enum Appearance: String, Codable, CaseIterable {
        case system, light, dark
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
