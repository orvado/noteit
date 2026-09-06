import Foundation

// MARK: - Token model

/// Universal token types across all languages. A theme colors each of
/// these; languages only decide which ranges produce which tokens.
enum SyntaxTokenType: String, CaseIterable, Codable {
    case plain
    case keyword
    case string
    case number
    case comment
    case type
    case functionCall
    case constant
    case attribute
    case preprocessor
}

struct SyntaxToken {
    let range: NSRange
    let type: SyntaxTokenType
}

// MARK: - Language definition

/// Regex rule set for one language. Comments and strings are scanned
/// position-aware as a first pass (so a `#` inside a string is not a
/// comment and a quote inside a comment is not a string); everything else
/// is layered onto the remaining gaps.
struct SyntaxDefinition {
    let commentPatterns: [NSRegularExpression]
    let stringPattern: NSRegularExpression?
    let numberPattern: NSRegularExpression?
    let keywordPattern: NSRegularExpression?
    let constantPattern: NSRegularExpression?
    let typePattern: NSRegularExpression?
    let attributePattern: NSRegularExpression?
    let preprocessorPattern: NSRegularExpression?

    /// `identifier(` — the identifier part (capture 1) becomes a function
    /// token. Keywords claimed earlier win, so `if (…)` stays a keyword.
    static let functionPattern = try! NSRegularExpression(
        pattern: "([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")

    static let genericNumber = try! NSRegularExpression(
        pattern: "\\b(?:0[xXbBoO][0-9a-fA-F_]+|\\d[\\d_]*(?:\\.[\\d_]+)?(?:[eE][+-]?\\d+)?)\\b")
}

extension Language {
    /// Syntax rules for this language, cached after first use.
    var syntax: SyntaxDefinition { SyntaxHighlighter.definition(for: self) }
}

// MARK: - Highlighter

enum SyntaxHighlighter {
    /// Definitions built once per language and reused — NSRegularExpression
    /// construction is far too expensive to repeat per keystroke.
    private static var cache: [Language: SyntaxDefinition] = [:]
    private static let lock = NSLock()

    static func definition(for language: Language) -> SyntaxDefinition {
        lock.lock(); defer { lock.unlock() }
        if let d = cache[language] { return d }
        let d = buildDefinition(for: language)
        cache[language] = d
        return d
    }

    /// Tokenizes `text`. Token ranges never overlap and never exceed the text.
    static func tokens(for language: Language, text: String) -> [SyntaxToken] {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return [] }
        let def = definition(for: language)

        // Pass 1 — comments and strings, leftmost-first, non-overlapping.
        var claimed: [(NSRange, SyntaxTokenType)] = []
        var candidates: [(NSRange, SyntaxTokenType)] = []
        for re in def.commentPatterns {
            re.enumerateMatches(in: text, range: NSRange(0..<length)) { m, _, _ in
                if let r = m?.range { candidates.append((r, .comment)) }
            }
        }
        if let re = def.stringPattern {
            re.enumerateMatches(in: text, range: NSRange(0..<length)) { m, _, _ in
                if let r = m?.range { candidates.append((r, .string)) }
            }
        }
        candidates.sort { $0.0.location < $1.0.location }
        for cand in candidates where !overlaps(claimed, cand.0) {
            claimed.append(cand)
        }
        claimed.sort { $0.0.location < $1.0.location }

        // Pass 2 — layered rules, only inside the gaps pass 1 left open.
        // Preprocessor lines and attributes run before numbers/keywords so
        // e.g. `#define MAX 100` stays one preprocessor token.
        var tokens = claimed.map { SyntaxToken(range: $0.0, type: $0.1) }
        let gaps = freeRanges(in: claimed, total: length)
        for (range, restrict) in gaps {
            append(&tokens, def.attributePattern, .attribute, in: text, range: restrict, claimed: &claimed)
            append(&tokens, def.preprocessorPattern, .preprocessor, in: text, range: restrict, claimed: &claimed)
            append(&tokens, def.numberPattern, .number, in: text, range: restrict, claimed: &claimed)
            append(&tokens, def.typePattern, .type, in: text, range: restrict, claimed: &claimed)
            append(&tokens, def.constantPattern, .constant, in: text, range: restrict, claimed: &claimed)
            append(&tokens, def.keywordPattern, .keyword, in: text, range: restrict, claimed: &claimed)
            append(&tokens, SyntaxDefinition.functionPattern, .functionCall, in: text, range: restrict,
                   claimed: &claimed, capture: 1)
        }
        tokens.sort { $0.range.location < $1.range.location }
        return tokens
    }

    // MARK: Scanning helpers

    private static func overlaps(_ claimed: [(NSRange, SyntaxTokenType)], _ r: NSRange) -> Bool {
        claimed.contains { NSIntersectionRange($0.0, r).length > 0 }
    }

    /// The maximal ranges not covered by any claimed range.
    private static func freeRanges(in claimed: [(NSRange, SyntaxTokenType)], total length: Int) -> [(NSRange, NSRange)] {
        var out: [(NSRange, NSRange)] = []
        var pos = 0
        for (r, _) in claimed {
            if r.location > pos {
                let gap = NSRange(location: pos, length: r.location - pos)
                out.append((gap, gap))
            }
            pos = max(pos, NSMaxRange(r))
        }
        if pos < length {
            let gap = NSRange(location: pos, length: length - pos)
            out.append((gap, gap))
        }
        return out
    }

    private static func append(_ tokens: inout [SyntaxToken],
                               _ rule: NSRegularExpression?,
                               _ type: SyntaxTokenType,
                               in text: String,
                               range: NSRange,
                               claimed: inout [(NSRange, SyntaxTokenType)],
                               capture: Int = 0) {
        guard let rule else { return }
        rule.enumerateMatches(in: text, range: range) { m, _, _ in
            guard let m else { return }
            let r = capture > 0 && m.numberOfRanges > capture
                ? m.range(at: capture)
                : m.range
            guard r.length > 0, !overlaps(claimed, r) else { return }
            claimed.append((r, type))
            tokens.append(SyntaxToken(range: r, type: type))
        }
    }

    // MARK: Rule builders

    private static func regex(_ pattern: String, anchor: Bool = false, caseInsensitive: Bool = false) -> NSRegularExpression {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        if anchor { opts.insert(.anchorsMatchLines) }
        return try! NSRegularExpression(pattern: pattern, options: opts)
    }

    /// `\b(?:kw1|kw2|…)\b` from a plain word list. Longest-first so e.g.
    /// `static_cast` wins over a future `static` conflict.
    private static func words(_ list: [String], caseInsensitive: Bool = false) -> NSRegularExpression {
        let alt = list.sorted { $0.count > $1.count }.map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return regex("\\b(?:\(alt))\\b", caseInsensitive: caseInsensitive)
    }

    private static func lineComment(_ prefix: String) -> NSRegularExpression {
        regex(NSRegularExpression.escapedPattern(for: prefix) + "[^\\n]*")
    }

    private static let blockComment = try! NSRegularExpression(pattern: "/\\*.*?\\*/", options: [.dotMatchesLineSeparators])

    /// Quote styles: pass the quote characters the language uses; both plain
    /// and escaped-content forms are matched. `triple` adds Python-style
    /// triple quotes (listed first so they win), `template` adds a template
    /// literal quote (JS/TS backtick), `multiline` lets strings span lines.
    private static func strings(_ quotes: String, triple: Bool = false, template: Character? = nil,
                                multiline: Bool = false) -> NSRegularExpression {
        var parts: [String] = []
        if triple {
            parts.append("\"\"\"(?:\\\\.|[^\\\\])*?\"\"\"")
            parts.append("'''(?:\\\\.|[^\\\\])*?'''")
        }
        func quoted(_ q: Character) {
            let e = NSRegularExpression.escapedPattern(for: String(q))
            // [^ q \ newline backslash ] plus backslash escapes; single-line
            // unless the language allows multi-line strings.
            let nl = multiline ? "" : "\\n"
            parts.append("\(e)(?:\\\\.|[^\\\\\(q)\(nl)])*\(e)")
        }
        for q in quotes { quoted(q) }
        if let t = template { quoted(t) }
        return regex(parts.joined(separator: "|"))
    }

    // MARK: Per-language definitions

    private static func buildDefinition(for lang: Language) -> SyntaxDefinition {
        switch lang {
        case .python:
            return SyntaxDefinition(
                commentPatterns: [lineComment("#")],
                stringPattern: strings("'\"", triple: true, multiline: true),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["def", "class", "import", "from", "as", "return", "if", "elif",
                                       "else", "for", "while", "break", "continue", "pass", "try",
                                       "except", "finally", "raise", "with", "yield", "lambda",
                                       "global", "nonlocal", "assert", "del", "in", "is", "not",
                                       "and", "or", "async", "await", "match", "case", "self", "cls"]),
                constantPattern: words(["True", "False", "None", "NotImplemented", "__name__"]),
                typePattern: words(["int", "str", "float", "bool", "list", "dict", "set", "tuple",
                                    "bytes", "object", "type", "Any", "Callable"]),
                attributePattern: regex("@[A-Za-z_][A-Za-z0-9_.]*"),
                preprocessorPattern: nil)

        case .javascript:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("'\"", template: "`"),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["function", "const", "let", "var", "return", "if", "else",
                                       "for", "while", "do", "switch", "case", "default", "break",
                                       "continue", "new", "delete", "typeof", "instanceof", "in",
                                       "of", "class", "extends", "super", "this", "import", "export",
                                       "from", "as", "try", "catch", "finally", "throw", "async",
                                       "await", "yield", "static", "get", "set"]),
                constantPattern: words(["true", "false", "null", "undefined", "NaN", "Infinity"]),
                typePattern: words(["number", "string", "boolean", "any", "void", "symbol",
                                    "bigint", "object", "never", "unknown"]),
                attributePattern: nil,
                preprocessorPattern: nil)

        case .typescript:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("'\"", template: "`"),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["function", "const", "let", "var", "return", "if", "else",
                                       "for", "while", "do", "switch", "case", "default", "break",
                                       "continue", "new", "delete", "typeof", "instanceof", "in",
                                       "of", "class", "extends", "implements", "super", "this",
                                       "import", "export", "from", "as", "try", "catch", "finally",
                                       "throw", "async", "await", "yield", "static", "get", "set",
                                       "interface", "type", "enum", "namespace", "declare", "keyof",
                                       "infer", "is", "asserts", "satisfies", "private", "public",
                                       "protected", "readonly", "abstract"]),
                constantPattern: words(["true", "false", "null", "undefined", "NaN", "Infinity"]),
                typePattern: words(["number", "string", "boolean", "any", "void", "symbol",
                                    "bigint", "object", "never", "unknown"]),
                attributePattern: regex("@[A-Za-z_][A-Za-z0-9_]*(?:\\([^)\\n]*\\))?"),
                preprocessorPattern: nil)

        case .java:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\"'"),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["public", "private", "protected", "static", "final", "abstract",
                                       "class", "interface", "extends", "implements", "enum", "record",
                                       "new", "return", "if", "else", "for", "while", "do", "switch",
                                       "case", "default", "break", "continue", "try", "catch",
                                       "finally", "throw", "throws", "import", "package", "this",
                                       "super", "instanceof", "synchronized", "volatile", "transient",
                                       "native", "var", "sealed", "permits", "assert", "yield"]),
                constantPattern: words(["true", "false", "null"]),
                typePattern: words(["int", "long", "short", "byte", "char", "float", "double",
                                    "boolean", "void", "String", "Integer", "Long", "Double", "List",
                                    "Map", "Set", "Optional", "ArrayList", "HashMap"]),
                attributePattern: regex("@[A-Za-z_][A-Za-z0-9_]*(?:\\([^)\\n]*\\))?"),
                preprocessorPattern: nil)

        case .csharp:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\"'"),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["public", "private", "protected", "internal", "static",
                                       "readonly", "const", "class", "struct", "interface", "enum",
                                       "record", "sealed", "abstract", "virtual", "override", "new",
                                       "return", "if", "else", "for", "foreach", "while", "do",
                                       "switch", "case", "default", "break", "continue", "try",
                                       "catch", "finally", "throw", "using", "namespace", "this",
                                       "base", "in", "out", "ref", "params", "var", "async", "await",
                                       "get", "set", "init", "where", "select", "from", "lock",
                                       "is", "as", "nameof", "when", "operator"]),
                constantPattern: words(["true", "false", "null"]),
                typePattern: words(["int", "uint", "long", "ulong", "short", "byte", "string", "bool",
                                    "char", "double", "decimal", "float", "object", "dynamic", "void",
                                    "nint", "Task", "List", "Dictionary", "IEnumerable"]),
                attributePattern: nil,
                preprocessorPattern: regex("^[ \\t]*#[A-Za-z_]+[^\\n]*", anchor: true))

        case .cpp:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\"'"),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["if", "else", "for", "while", "do", "switch", "case", "default",
                                       "break", "continue", "return", "goto", "class", "struct",
                                       "union", "enum", "typedef", "template", "typename", "namespace",
                                       "using", "public", "private", "protected", "virtual", "override",
                                       "new", "delete", "this", "const", "static", "constexpr", "inline",
                                       "extern", "mutable", "volatile", "auto", "sizeof", "alignof",
                                       "static_cast", "dynamic_cast", "reinterpret_cast", "const_cast",
                                       "try", "catch", "throw", "noexcept", "operator"]),
                constantPattern: words(["true", "false", "nullptr", "NULL"]),
                typePattern: words(["int", "char", "float", "double", "void", "bool", "long", "short",
                                    "unsigned", "signed", "size_t", "wchar_t", "FILE", "std"]),
                attributePattern: regex("\\[\\[[A-Za-z_][A-Za-z0-9_]*\\]\\]"),
                preprocessorPattern: regex("^[ \\t]*#[A-Za-z_]+[^\\n]*", anchor: true))

        case .sql:
            // SQL escapes quotes by doubling them: 'it''s' is one string.
            let sqlStrings = try! NSRegularExpression(
                pattern: "'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"")
            return SyntaxDefinition(
                commentPatterns: [lineComment("--"), blockComment],
                stringPattern: sqlStrings,
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE",
                                       "SET", "DELETE", "CREATE", "TABLE", "ALTER", "DROP", "ADD",
                                       "COLUMN", "VIEW", "INDEX", "JOIN", "INNER", "LEFT", "RIGHT",
                                       "OUTER", "FULL", "CROSS", "ON", "AS", "AND", "OR", "NOT", "IS",
                                       "IN", "BETWEEN", "LIKE", "EXISTS", "GROUP", "BY", "HAVING",
                                       "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "UNION", "ALL",
                                       "DISTINCT", "CASE", "WHEN", "THEN", "ELSE", "END", "PRIMARY",
                                       "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE",
                                       "CONSTRAINT", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
                                       "WITH", "RETURNING", "OVER", "PARTITION", "WINDOW"],
                                      caseInsensitive: true),
                constantPattern: words(["NULL", "TRUE", "FALSE", "CURRENT_TIMESTAMP", "CURRENT_DATE"],
                                       caseInsensitive: true),
                typePattern: words(["INTEGER", "INT", "BIGINT", "SMALLINT", "VARCHAR", "CHAR", "TEXT",
                                    "BOOLEAN", "DATE", "TIMESTAMP", "DECIMAL", "NUMERIC", "FLOAT",
                                    "REAL", "DOUBLE", "SERIAL", "BLOB", "JSON"],
                                   caseInsensitive: true),
                attributePattern: nil,
                preprocessorPattern: nil)

        case .go:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\"'`", multiline: true),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["package", "import", "func", "return", "if", "else", "for",
                                       "range", "switch", "case", "default", "break", "continue",
                                       "fallthrough", "goto", "defer", "go", "chan", "select", "map",
                                       "struct", "interface", "type", "var", "const"]),
                constantPattern: words(["true", "false", "nil", "iota"]),
                typePattern: words(["int", "int8", "int16", "int32", "int64", "uint", "uint8",
                                    "uint16", "uint32", "uint64", "uintptr", "float32", "float64",
                                    "complex64", "complex128", "string", "bool", "byte", "rune",
                                    "error", "any"]),
                attributePattern: nil,
                preprocessorPattern: nil)

        case .rust:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\""),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["fn", "let", "mut", "const", "static", "struct", "enum", "trait",
                                       "impl", "for", "in", "if", "else", "while", "loop", "match",
                                       "break", "continue", "return", "use", "mod", "pub", "crate",
                                       "self", "super", "as", "dyn", "ref", "move", "async", "await",
                                       "unsafe", "where", "type", "union"]),
                constantPattern: words(["true", "false", "None", "Some", "Ok", "Err"]),
                typePattern: words(["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32",
                                    "u64", "u128", "usize", "f32", "f64", "bool", "char", "str",
                                    "String", "Vec", "Option", "Result", "Box", "HashMap"]),
                attributePattern: regex("#\\[[^\\]\\n]*\\]|#!\\[[^\\]\\n]*\\]"),
                preprocessorPattern: nil)

        case .kotlin:
            return SyntaxDefinition(
                commentPatterns: [lineComment("//"), blockComment],
                stringPattern: strings("\""),
                numberPattern: SyntaxDefinition.genericNumber,
                keywordPattern: words(["fun", "val", "var", "class", "object", "interface", "enum",
                                       "sealed", "data", "abstract", "open", "final", "override",
                                       "private", "public", "protected", "internal", "companion",
                                       "init", "constructor", "return", "if", "else", "when", "for",
                                       "while", "do", "break", "continue", "try", "catch", "finally",
                                       "throw", "import", "package", "this", "super", "is", "in",
                                       "as", "by", "where", "lateinit", "lazy", "suspend", "inline",
                                       "operator", "infix", "vararg", "out", "reified", "crossinline",
                                       "typealias", "subject"]),
                constantPattern: words(["true", "false", "null", "it"]),
                typePattern: words(["Int", "Long", "Short", "Byte", "Double", "Float", "Boolean",
                                    "Char", "String", "Unit", "Any", "Nothing", "List", "Map", "Set",
                                    "MutableList", "MutableMap"]),
                attributePattern: regex("@[A-Za-z_][A-Za-z0-9_]*(?:\\([^)\\n]*\\))?"),
                preprocessorPattern: nil)
        }
    }
}
