import SwiftUI
import AppKit

/// The About NoteIt sheet: app identity, feature overview, author credit
/// and the full Apache License 2.0 text.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @State private var showLicense = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?): return "Version \(s) (\(b))"
        case let (s?, nil): return "Version \(s)"
        default: return "Version 1.0 (dev)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 20).padding(.bottom, 14)
            Divider()
            features
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(14)
        }
        .frame(width: 560, height: 620)
    }

    // MARK: Subviews

    private var header: some View {
        HStack(spacing: 18) {
            AboutIcon()
            VStack(alignment: .leading, spacing: 4) {
                Text("NoteIt").font(.title).fontWeight(.bold)
                Text(version).font(.caption).foregroundStyle(.secondary)
                Text("A fast, native macOS text editor for notes and code.")
                    .font(.callout)
                HStack(spacing: 4) {
                    Text("Created by").font(.caption).foregroundStyle(.secondary)
                    Button("Ken Richards") {
                        openURL(URL(string: "mailto:kenr@orvado.com")!)
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Button("kenr@orvado.com") {
                        openURL(URL(string: "mailto:kenr@orvado.com")!)
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
                .padding(.top, 2)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var features: some View {
        ScrollView {
            let items: [(icon: String, title: String, detail: String)] = [
                ("rectangle.stack", "Tabs & windows", "Multiple documents in tabs, draft recovery on launch"),
                ("magnifyingglass", "Find & replace", "Regex, whole-word, case, wrap-around, live match count"),
                ("text.badge.plus", "Snippets", "Trigger + Tab expansion, placeholders, {date}/{time}"),
                ("square.grid.2x2", "10 language packs", "~30 built-in snippets each for Python, JS, Java, C#, C/C++, TypeScript, SQL, Go, Rust and Kotlin"),
                ("globe", "Active language", "Detected per tab from extension or content; manual override in the status bar"),
                ("clock.arrow.circlepath", "Auto-save", "Configurable interval, untitled drafts kept safe"),
                ("doc.text.magnifyingglass", "Quick open", "⌘P fuzzy access to recent files"),
                ("text.justify", "Editor essentials", "Line numbers, word wrap, spellcheck, go-to-line, font control"),
                ("arrow.up.doc", "Export & print", "Save as PDF or plain text, native printing"),
                ("moon", "Native look", "Light/dark appearance, fast launch, plain-text UTF-8 throughout"),
            ]
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                      alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.element.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.element.title).font(.callout).fontWeight(.medium)
                            Text(item.element.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(20)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("© 2026 Ken Richards. Released under the Apache License 2.0.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(showLicense ? "Hide License" : "View License") {
                    withAnimation { showLicense.toggle() }
                }
            }
            if showLicense {
                ScrollView {
                    Text(apacheLicenseText)
                        .font(.system(size: 9.5, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 170)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// Small SwiftUI replica of the app icon (see scripts/make-icon.swift) so
/// the About box shows the branded icon even when running unbundled via
/// `swift run`.
private struct AboutIcon: View {
    private static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0.29, green: 0.43, blue: 0.93),
            Color(red: 0.55, green: 0.34, blue: 0.95),
            Color(red: 0.90, green: 0.28, blue: 0.72),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Card silhouette with the folded (cut) top-right corner. Corners are
    /// quadratic curves — no arc-direction ambiguity between coordinate
    /// systems.
    private struct FoldedCard: Shape {
        var fold: CGFloat
        var radius: CGFloat

        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            p.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                           control: CGPoint(x: rect.minX, y: rect.minY))
            p.closeSubpath()
            return p
        }
    }

    var body: some View {
        let cardW: CGFloat = 62, cardH: CGFloat = 78
        let fold: CGFloat = 14
        let innerW: CGFloat = cardW - 16
        let lines: [(width: CGFloat, color: Color)] = [
            (0.62, Color(red: 0.388, green: 0.396, blue: 0.945)),
            (0.80, Color(red: 0.976, green: 0.463, blue: 0.094)),
            (0.52, Color(red: 0.184, green: 0.722, blue: 0.502)),
            (0.72, Color(red: 0.231, green: 0.510, blue: 0.965)),
            (0.34, Color(red: 0.580, green: 0.639, blue: 0.729)),
        ]
        return ZStack {
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .fill(Self.bgGradient)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

            ZStack(alignment: .topLeading) {
                FoldedCard(fold: fold, radius: 7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

                // Folded-corner flap: back side of the page.
                Path { p in
                    p.move(to: CGPoint(x: cardW - fold, y: 0))
                    p.addLine(to: CGPoint(x: cardW, y: fold))
                    p.addLine(to: CGPoint(x: cardW - fold, y: fold))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.914, green: 0.929, blue: 0.965))

                // Syntax-colored text lines, caret after the last one.
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(lines.indices, id: \.self) { i in
                        HStack(spacing: 5) {
                            Capsule().fill(lines[i].color)
                                .frame(width: innerW * lines[i].width, height: 5)
                            if i == lines.indices.last {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color(red: 0.310, green: 0.275, blue: 0.898))
                                    .frame(width: 3, height: 11)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 10)
            }
            .frame(width: cardW, height: cardH)
        }
        .frame(width: 128, height: 128)
    }
}
