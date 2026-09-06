import AppKit

// MARK: - Theme model

/// A syntax color scheme: one color per token type plus a background and a
/// plain-text color. Themes are pure data — adding one is a new entry in
/// `HighlightTheme.all`.
struct HighlightTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool
    let background: NSColor
    let plain: NSColor
    let keyword: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let type: NSColor
    let functionCall: NSColor
    let constant: NSColor
    let attribute: NSColor
    let preprocessor: NSColor

    func color(for token: SyntaxTokenType) -> NSColor {
        switch token {
        case .plain: return plain
        case .keyword: return keyword
        case .string: return string
        case .number: return number
        case .comment: return comment
        case .type: return type
        case .functionCall: return functionCall
        case .constant: return constant
        case .attribute: return attribute
        case .preprocessor: return preprocessor
        }
    }

    /// Omit colors that fall back to the plain color when rendering small
    /// previews (keeps the swatch row tidy).
    var swatch: [NSColor] { [keyword, string, comment, type, functionCall, number] }
}

enum HighlightThemeCatalog {
    /// Settings value meaning "no highlighting" — not a theme instance.
    static let noneID = "none"

    static let all: [HighlightTheme] = [paper, daylight, solarLight, midnight, monokai, nord, dracula, sunset, forest]

    static func resolve(_ id: String) -> HighlightTheme? {
        id == noneID ? nil : all.first(where: { $0.id == id })
    }

    // MARK: Themes

    private static func hex(_ rgb: UInt32) -> NSColor {
        NSColor(red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
                green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
                blue: CGFloat(rgb & 0xFF) / 255.0,
                alpha: 1)
    }

    private static func theme(_ id: String, _ name: String, dark: Bool, bg: UInt32, plain: UInt32,
                              kw: UInt32, str: UInt32, num: UInt32, com: UInt32, typ: UInt32,
                              fn: UInt32, const: UInt32, attr: UInt32, prep: UInt32) -> HighlightTheme {
        HighlightTheme(id: id, name: name, isDark: dark,
                       background: hex(bg), plain: hex(plain),
                       keyword: hex(kw), string: hex(str), number: hex(num), comment: hex(com),
                       type: hex(typ), functionCall: hex(fn), constant: hex(const),
                       attribute: hex(attr), preprocessor: hex(prep))
    }

    /// GitHub-Light-inspired: crisp classic IDE colors on white.
    static let paper = theme("paper", "Paper", dark: false,
        bg: 0xFFFFFF, plain: 0x1F2328,
        kw: 0xCF222E, str: 0x0A3069, num: 0x0550AE, com: 0x6E7781,
        typ: 0x8250DF, fn: 0x953800, const: 0x0550AE, attr: 0x116329, prep: 0x57606A)

    /// One-Light-inspired: soft, warm light scheme.
    static let daylight = theme("daylight", "Daylight", dark: false,
        bg: 0xFAFAFA, plain: 0x383A42,
        kw: 0xA626A4, str: 0x50A14F, num: 0x986801, com: 0xA0A1A7,
        typ: 0x0184BC, fn: 0x4078F2, const: 0xE45649, attr: 0xC18401, prep: 0xA0A1A7)

    /// Solarized Light.
    static let solarLight = theme("solarlight", "Solar Light", dark: false,
        bg: 0xFDF6E3, plain: 0x586E75,
        kw: 0x859900, str: 0x2AA198, num: 0xD33682, com: 0x93A1A1,
        typ: 0x268BD2, fn: 0x268BD2, const: 0xCB4B16, attr: 0xB58900, prep: 0x93A1A1)

    /// Dark+ inspired: the classic dark IDE look.
    static let midnight = theme("midnight", "Midnight", dark: true,
        bg: 0x1E1E1E, plain: 0xD4D4D4,
        kw: 0x569CD6, str: 0xCE9178, num: 0xB5CEA8, com: 0x6A9955,
        typ: 0x4EC9B0, fn: 0xDCDCAA, const: 0x569CD6, attr: 0xDCDCAA, prep: 0xC586C0)

    /// Monokai.
    static let monokai = theme("monokai", "Monokai", dark: true,
        bg: 0x272822, plain: 0xF8F8F2,
        kw: 0xF92672, str: 0xE6DB74, num: 0xAE81FF, com: 0x75715E,
        typ: 0x66D9EF, fn: 0xA6E22E, const: 0xAE81FF, attr: 0xA6E22E, prep: 0x75715E)

    /// Nord.
    static let nord = theme("nord", "Nord", dark: true,
        bg: 0x2E3440, plain: 0xD8DEE9,
        kw: 0x81A1C1, str: 0xA3BE8C, num: 0xB48EAD, com: 0x616E88,
        typ: 0x8FBCBB, fn: 0x88C0D0, const: 0x8FBCBB, attr: 0x8FBCBB, prep: 0x5E81AC)

    /// Dracula.
    static let dracula = theme("dracula", "Dracula", dark: true,
        bg: 0x282A36, plain: 0xF8F8F2,
        kw: 0xFF79C6, str: 0xF1FA8C, num: 0xBD93F9, com: 0x6272A4,
        typ: 0x8BE9FD, fn: 0x50FA7B, const: 0xBD93F9, attr: 0x50FA7B, prep: 0x6272A4)

    /// Gruvbox-inspired warm dark scheme.
    static let sunset = theme("sunset", "Sunset", dark: true,
        bg: 0x282828, plain: 0xEBDBB2,
        kw: 0xFB4934, str: 0xB8BB26, num: 0xD3869B, com: 0x928374,
        typ: 0xFABD2F, fn: 0x8EC07C, const: 0xD3869B, attr: 0x83A598, prep: 0x928374)

    /// Deep green dark scheme for long sessions.
    static let forest = theme("forest", "Forest", dark: true,
        bg: 0x1B2220, plain: 0xDBE2D9,
        kw: 0x7FB383, str: 0xD6B678, num: 0xC0899B, com: 0x6B7D71,
        typ: 0x86C0B4, fn: 0xA8CE93, const: 0xD2A26E, attr: 0x9CB8AA, prep: 0x6B7D71)
}
