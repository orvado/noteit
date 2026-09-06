import SwiftUI
import AppKit

// MARK: - Model

/// One matching line in one workspace file.
struct WorkspaceMatch: Identifiable {
    let id = UUID()
    let fileURL: URL
    /// 1-based line number in the file.
    let lineNumber: Int
    /// The line with leading whitespace trimmed, for display.
    let displayLine: String
    /// Match range within `displayLine` (UTF16 units).
    let displayMatchRange: NSRange
    /// Which match (0-based) this is within its line — used to re-locate it
    /// reliably in the live text when a replacement is applied.
    let matchIndexInLine: Int
    /// Match range within the file's full text at search time — used to
    /// reveal the match; clamped by the receiver if the file has drifted.
    let fileRange: NSRange
}

/// All matches for one file.
struct WorkspaceFileResults: Identifiable {
    let id = UUID()
    let fileURL: URL
    let matches: [WorkspaceMatch]
}

/// Search-and-replace state for the workspace pane. Searching runs off the
/// main thread; replacements are applied only on explicit confirmation.
@MainActor
final class WorkspaceSearchStore: ObservableObject {
    @Published var query = ""
    @Published var replacement = ""
    @Published var caseSensitive = false
    @Published var useRegex = false
    @Published var isRunning = false
    @Published private(set) var results: [WorkspaceFileResults] = []

    nonisolated static let maxResults = 1000
    nonisolated static let maxFileSize = 2_000_000
    private var searchTask: Task<Void, Never>?

    var matchCount: Int { results.reduce(0) { $0 + $1.matches.count } }
    var fileCount: Int { results.count }

    // MARK: Search

    func cancel() {
        searchTask?.cancel()
        isRunning = false
    }

    /// Runs the search over `root`. Safe to call repeatedly — a new search
    /// cancels the previous one.
    func run(root: URL?) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let root, !q.isEmpty else {
            results = []
            isRunning = false
            return
        }
        isRunning = true
        let cs = caseSensitive, rx = useRegex
        searchTask = Task.detached { [weak self] in
            let found = Self.searchFiles(root: root, query: q, caseSensitive: cs, regex: rx)
            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else { return }
                self.results = found
                self.isRunning = false
            }
        }
    }

    /// Synchronous file walk + match scan; runs detached from the main actor.
    nonisolated private static func searchFiles(root: URL, query: String,
                                                caseSensitive: Bool, regex: Bool) -> [WorkspaceFileResults] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in false })
        else { return [] }

        var total = 0
        var found: [WorkspaceFileResults] = []
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard total < maxResults else { break }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= maxFileSize else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  !text.contains("\0")
            else { continue }
            let matches = matches(in: text, fileURL: url, query: query,
                                  caseSensitive: caseSensitive, regex: regex,
                                  limit: maxResults - total)
            if !matches.isEmpty {
                found.append(WorkspaceFileResults(fileURL: url, matches: matches))
                total += matches.count
            }
        }
        return found
    }

    /// All matches in `text`, one per result line, with display info.
    nonisolated static func matches(in text: String, fileURL: URL, query: String,
                                    caseSensitive: Bool, regex: Bool, limit: Int) -> [WorkspaceMatch] {
        let ns = text as NSString
        guard ns.length > 0, !query.isEmpty else { return [] }
        let ranges = findRanges(of: query, in: text, caseSensitive: caseSensitive, regex: regex)
        guard !ranges.isEmpty else { return [] }

        // Line starts for line-number lookups (binary-searched per match).
        var lineStarts: [Int] = [0]
        var search = NSRange(location: 0, length: ns.length)
        while true {
            let r = ns.range(of: "\n", range: search)
            if r.location == NSNotFound { break }
            lineStarts.append(NSMaxRange(r))
            search = NSRange(location: NSMaxRange(r), length: NSMaxRange(search) - NSMaxRange(r))
            if search.length <= 0 { break }
        }

        var out: [WorkspaceMatch] = []
        out.reserveCapacity(min(ranges.count, limit))
        var perLineCounts: [Int: Int] = [:]
        for range in ranges.prefix(limit) {
            // Line containing the match start.
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= range.location { lo = mid } else { hi = mid - 1 }
            }
            let lineStart = lineStarts[lo]
            let lineEndRaw = (lo + 1 < lineStarts.count) ? lineStarts[lo + 1] - 1 : ns.length
            let lineEnd = lineEndRaw
            let lineRange = NSRange(location: lineStart, length: max(0, lineEnd - lineStart))
            let fullLine = ns.substring(with: lineRange)
            let trimmed = fullLine.trimmingCharacters(in: .whitespaces)
            let trimmedOffset = fullLine.count - trimmed.count

            let line = lo + 1
            let index = perLineCounts[line] ?? 0
            perLineCounts[line] = index + 1

            let displayMatch = NSRange(location: range.location - lineStart - trimmedOffset,
                                       length: range.length)
            out.append(WorkspaceMatch(
                fileURL: fileURL,
                lineNumber: line,
                displayLine: trimmed,
                displayMatchRange: displayMatch,
                matchIndexInLine: index,
                fileRange: range))
        }
        return out
    }

    /// Plain or regex ranges of `query` in `text` (mirrors the editor find).
    nonisolated static func findRanges(of query: String, in text: String,
                                       caseSensitive: Bool, regex: Bool) -> [NSRange] {
        let ns = text as NSString
        guard !query.isEmpty, ns.length > 0 else { return [] }
        if regex {
            do {
                var opts: NSRegularExpression.Options = [.anchorsMatchLines]
                if !caseSensitive { opts.insert(.caseInsensitive) }
                let re = try NSRegularExpression(pattern: query, options: opts)
                return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { $0.range }
            } catch { return [] }
        }
        var opts: NSString.CompareOptions = []
        if !caseSensitive { opts.insert(.caseInsensitive) }
        var out: [NSRange] = []
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let r = ns.range(of: query, options: opts, range: search)
            if r.location == NSNotFound { break }
            out.append(r)
            let next = r.location + max(1, r.length)
            if next >= ns.length { break }
            search = NSRange(location: next, length: ns.length - next)
        }
        return out
    }

    // MARK: Replace

    /// The line with the replacement applied, plus the range of the inserted
    /// text — the per-row "preview the replace" rendering.
    func previewLine(for match: WorkspaceMatch) -> (line: String, insertedRange: NSRange) {
        let ns = match.displayLine as NSString
        guard match.displayMatchRange.location >= 0,
              NSMaxRange(match.displayMatchRange) <= ns.length else {
            return (match.displayLine, NSRange(location: 0, length: 0))
        }
        let replaced = NSMutableString(string: match.displayLine)
        replaced.replaceCharacters(in: match.displayMatchRange, with: replacement)
        return (replaced as String,
                NSRange(location: match.displayMatchRange.location, length: (replacement as NSString).length))
    }

    /// Confirms one result row: replaces just that match. Edits go through
    /// an open editing tab when one exists (keeping its dirty state honest),
    /// otherwise straight to disk; preview tabs follow the file.
    func replaceOne(_ match: WorkspaceMatch, in store: DocumentStore, root: URL?) {
        applyReplacement(fileURL: match.fileURL,
                         lineNumber: match.lineNumber,
                         matchIndexInLine: match.matchIndexInLine,
                         all: false, store: store)
        refresh(fileURL: match.fileURL, root: root)
    }

    /// Replace-everything path, called only after the "Are you sure?"
    /// confirmation. Applies to every result file, then re-runs the search.
    func replaceAll(store: DocumentStore, root: URL?) {
        let files = results.map(\.fileURL)
        for url in files {
            applyReplacement(fileURL: url, lineNumber: nil, matchIndexInLine: nil,
                             all: true, store: store)
        }
        run(root: root)
    }

    /// Re-searches a single file and swaps its group in the results.
    private func refresh(fileURL: URL, root: URL?) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            results.removeAll { $0.fileURL == fileURL }
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let newMatches = Self.matches(in: text, fileURL: fileURL, query: q,
                                       caseSensitive: caseSensitive, regex: useRegex,
                                       limit: Self.maxResults)
        if let idx = results.firstIndex(where: { $0.fileURL == fileURL }) {
            if newMatches.isEmpty { results.remove(at: idx) }
            else { results[idx] = WorkspaceFileResults(fileURL: fileURL, matches: newMatches) }
        } else if !newMatches.isEmpty {
            results.append(WorkspaceFileResults(fileURL: fileURL, matches: newMatches))
        }
    }

    /// Replaces the `matchIndexInLine`-th match on `lineNumber` (or every
    /// match with `all`) in the live text: an open editing tab's text when
    /// one exists, otherwise the file on disk.
    private func applyReplacement(fileURL: URL, lineNumber: Int?, matchIndexInLine: Int?,
                                  all: Bool, store: DocumentStore) {
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let doc = store.documents.first(where: { !$0.isPreview && $0.fileURL == fileURL }) {
            // Edit through the open tab so dirty state and undo stay honest.
            guard let newText = Self.replace(in: doc.text, query: query, replacement: replacement,
                                             caseSensitive: caseSensitive, regex: useRegex,
                                             lineNumber: lineNumber, matchIndexInLine: matchIndexInLine, all: all),
                  newText != doc.text
            else { NSSound.beep(); return }
            if let tv = store.textViews[doc.id] {
                tv.string = newText
                store.syncFromTextView(tv, to: doc)
            } else {
                doc.text = newText
            }
            return
        }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8),
              let newText = Self.replace(in: text, query: query, replacement: replacement,
                                         caseSensitive: caseSensitive, regex: useRegex,
                                         lineNumber: lineNumber, matchIndexInLine: matchIndexInLine, all: all),
              newText != text
        else { NSSound.beep(); return }
        do {
            try newText.write(to: fileURL, atomically: true, encoding: .utf8)
            // Keep any open preview of this file in sync.
            if let preview = store.documents.first(where: { $0.isPreview && $0.fileURL == fileURL }) {
                preview.text = newText
                preview.isDirty = false
                if let tv = store.textViews[preview.id] { tv.string = newText }
            }
        } catch {
            NSSound.beep()
        }
    }

    /// Core replacement. With `all`, replaces every match; otherwise only
    /// the `matchIndexInLine`-th match on `lineNumber`. Returns nil when the
    /// located match no longer exists (file drifted).
    nonisolated private static func replace(in text: String, query: String, replacement: String,
                                            caseSensitive: Bool, regex: Bool,
                                            lineNumber: Int?, matchIndexInLine: Int?, all: Bool) -> String? {
        let ns = text as NSString
        if all {
            let ranges = findRanges(of: query, in: text, caseSensitive: caseSensitive, regex: regex)
            guard !ranges.isEmpty else { return nil }
            let template = NSRegularExpression.escapedTemplate(for: replacement)
            if regex {
                do {
                    var opts: NSRegularExpression.Options = [.anchorsMatchLines]
                    if !caseSensitive { opts.insert(.caseInsensitive) }
                    let re = try NSRegularExpression(pattern: query, options: opts)
                    let m = NSMutableString(string: text)
                    re.replaceMatches(in: m, range: NSRange(location: 0, length: ns.length),
                                      withTemplate: template)
                    return m as String
                } catch { return nil }
            }
            let m = NSMutableString(string: text)
            for r in ranges.reversed() { m.replaceCharacters(in: r, with: replacement) }
            return m as String
        }

        // Single match on a specific line.
        guard let lineNumber, let matchIndexInLine else { return nil }
        var lineStart = 0
        var currentLine = 1
        while currentLine < lineNumber {
            let r = ns.range(of: "\n", range: NSRange(location: lineStart, length: ns.length - lineStart))
            if r.location == NSNotFound { return nil }
            lineStart = NSMaxRange(r)
            currentLine += 1
        }
        let lineEndRange = ns.range(of: "\n", range: NSRange(location: lineStart, length: ns.length - lineStart))
        let lineEnd = lineEndRange.location == NSNotFound ? ns.length : lineEndRange.location
        let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
        let line = ns.substring(with: lineRange)
        let ranges = findRanges(of: query, in: line, caseSensitive: caseSensitive, regex: regex)
        guard ranges.indices.contains(matchIndexInLine) else { return nil }
        let target = ranges[matchIndexInLine]
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: NSRange(location: lineStart + target.location, length: target.length),
                            with: replacement)
        return m as String
    }
}

// MARK: - Search pane

/// The left-pane workspace search: query/replace controls and grouped
/// results. Single click previews the file at the match; double click opens
/// it for editing; the ✓ button confirms a single replacement (nothing is
/// written before that); Replace All asks "Are you sure?" first.
struct WorkspaceSearchPane: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var search: WorkspaceSearchStore
    @FocusState private var queryFocused: Bool
    @State private var showReplace = false
    @State private var previewReplacements = true
    @State private var confirmReplaceAll = false

    private var root: URL? { store.workspace.rootURL }

    var body: some View {
        VStack(spacing: 0) {
            if root == nil {
                emptyState
            } else {
                controls
                Divider()
                results
            }
        }
        .onAppear { queryFocused = true }
        .alert("Replace All?", isPresented: $confirmReplaceAll) {
            Button("Cancel", role: .cancel) { }
            Button("Replace All", role: .destructive) {
                search.replaceAll(store: store, root: root)
            }
        } message: {
            Text("Replaces \(search.matchCount) match\(search.matchCount == 1 ? "" : "es") across \(search.fileCount) file\(search.fileCount == 1 ? "" : "s"). Files on disk are edited — this cannot be undone.")
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search workspace", text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($queryFocused)
                    .onSubmit { search.run(root: root) }
                Button(action: { search.run(root: root) }) {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.borderless)
                .help("Run search (⏎)")
            }
            HStack(spacing: 2) {
                Button("Aa") { search.caseSensitive.toggle() }
                    .buttonStyle(.borderless)
                    .tint(search.caseSensitive ? .accentColor : .secondary)
                    .help("Case sensitive")
                Button(".*") { search.useRegex.toggle() }
                    .buttonStyle(.borderless)
                    .tint(search.useRegex ? .accentColor : .secondary)
                    .help("Regular expression")
                Spacer()
                if search.isRunning { ProgressView().controlSize(.small) }
                else if !search.query.isEmpty {
                    Text("\(search.matchCount) match\(search.matchCount == 1 ? "" : "es") in \(search.fileCount) file\(search.fileCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 4) {
                Button(action: { withAnimation { showReplace.toggle() } }) {
                    Image(systemName: showReplace ? "chevron.up.square" : "chevron.down.square")
                }
                .buttonStyle(.borderless)
                .help("Toggle replace")
                if showReplace {
                    TextField("Replace", text: $search.replacement)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { previewReplacements.toggle() }) {
                        Image(systemName: previewReplacements ? "eye.fill" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help("Preview replacements in the results")
                    Button(action: { confirmReplaceAll = true }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .disabled(search.matchCount == 0 || search.isRunning)
                    .help("Replace all matches…")
                }
            }
        }
        .padding(8)
    }

    // MARK: Results

    private var results: some View {
        Group {
            if search.isRunning && search.results.isEmpty {
                HStack { Spacer(); ProgressView("Searching…"); Spacer() }
                    .padding(.top, 24)
            } else if search.query.trimmingCharacters(in: .whitespaces).isEmpty {
                hint("Type a query and press ⏎ to search the workspace.")
            } else if search.results.isEmpty {
                hint("No matches.")
            } else {
                resultList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resultList: some View {
        List {
            ForEach(search.results) { group in
                Section {
                    ForEach(group.matches) { match in
                        MatchRow(
                            match: match,
                            search: search,
                            replaceMode: showReplace,
                            previewReplacement: showReplace && previewReplacements,
                            onPreview: { store.openPreviewSelecting(url: match.fileURL, range: match.fileRange) },
                            onEdit: { store.openForEditingSelecting(url: match.fileURL, range: match.fileRange) },
                            onReplace: { search.replaceOne(match, in: store, root: root) })
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                        Text(group.fileURL.lastPathComponent)
                        Text("· \(group.matches.count)")
                        Spacer()
                    }
                    .help(group.fileURL.path)
                }
            }
            if search.matchCount >= WorkspaceSearchStore.maxResults {
                Text("Showing the first \(WorkspaceSearchStore.maxResults) matches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    private func hint(_ text: String) -> some View {
        HStack { Spacer(); Text(text).font(.caption).foregroundStyle(.secondary); Spacer() }
            .padding(.top, 24)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No Workspace")
                .font(.headline)
            Text("Open a folder to search across its files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Folder…") {
                NotificationCenter.default.post(name: .noteItOpenFolder, object: nil)
            }
            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One result line: line number, the line with the match highlighted (or the
/// replacement previewed when replace mode is on), and the small confirm
/// button for a single replacement.
private struct MatchRow: View {
    let match: WorkspaceMatch
    @ObservedObject var search: WorkspaceSearchStore
    var replaceMode: Bool
    var previewReplacement: Bool
    var onPreview: () -> Void
    var onEdit: () -> Void
    var onReplace: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(match.lineNumber)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
            Text(lineText)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if replaceMode {
                Button(action: onReplace) { Image(systemName: "checkmark.circle") }
                    .buttonStyle(.borderless)
                    .help("Replace this match with “\(search.replacement)”")
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        // Double first: a double click also fires the single-tap preview and
        // then promotes it, mirroring the explorer's click behavior.
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture(count: 1) { onPreview() }
    }

    private var lineText: AttributedString {
        if previewReplacement, !search.replacement.isEmpty {
            let p = search.previewLine(for: match)
            return Self.highlighted(p.line, range: p.insertedRange, color: .systemGreen.withAlphaComponent(0.35))
        }
        return Self.highlighted(match.displayLine, range: match.displayMatchRange,
                                color: .systemYellow.withAlphaComponent(0.45))
    }

    /// UTF16-range-safe highlighting via the NSAttributedString bridge.
    private static func highlighted(_ line: String, range: NSRange, color: NSColor) -> AttributedString {
        let ns = NSMutableAttributedString(string: line)
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: (line as NSString).length))
        if clamped.length > 0 || (clamped.location == 0 && (line as NSString).length == 0) {
            ns.addAttribute(.backgroundColor, value: color, range: clamped)
        }
        return AttributedString(ns)
    }
}
