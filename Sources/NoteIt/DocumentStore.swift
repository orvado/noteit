import Foundation
import AppKit
import SwiftUI
import Combine

// MARK: - Session restore

/// One tab in the persisted session: either a file on disk or an auto-saved
/// untitled draft.
struct SessionEntry: Codable {
    var filePath: String?
    var draftFile: String?
}

/// The tab session persisted across launches: which tabs were open (in
/// order) and which one was selected.
struct SessionState: Codable {
    var entries: [SessionEntry] = []
    var selectedIndex: Int = 0
}

@MainActor
final class DocumentStore: ObservableObject {
    @Published var documents: [EditorDocument] = []
    @Published var selectedID: UUID?
    @Published var settings = AppSettings()
    @Published var snippets: [TextSnippet] = TextSnippet.defaults
    @Published var recentFiles: [URL] = []
    @Published var search = SearchOptions()
    /// Language packs the user has included; only these show in the snippet
    /// manager and only the active document's pack expands in the editor.
    @Published var enabledLanguages: Set<Language> = []
    /// Per-pack snippets, keyed by `Language.rawValue`. Entries deliberately
    /// survive disabling a pack so user edits are still there when the pack
    /// is re-enabled later.
    @Published var languagePackSnippets: [String: [TextSnippet]] = [:]
    /// The open workspace folder (file explorer pane), restored on launch.
    let workspace = WorkspaceStore()

    /// Weak registry of live NSTextViews per document, for find/goto/print.
    var textViews: [UUID: NSTextView] = [:]
    private var autosaveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    /// Live snippet-placeholder navigation session, if any.
    /// See "Snippet placeholders" below.
    private var placeholderSession: PlaceholderSession?
    /// Per-document isDirty subscriptions, republished so the file explorer
    /// re-renders its green "unsaved" markers when tabs change state.
    private var docObservers: [UUID: AnyCancellable] = [:]

    var selectedDocument: EditorDocument? {
        guard let id = selectedID else { return documents.first }
        return documents.first(where: { $0.id == id }) ?? documents.first
    }

    /// The theme id actually in effect: the user's choice, or — when a theme
    /// was never picked manually — an appearance-matched default (Paper for
    /// light, Monokai for dark). Uses the app's effective appearance, which
    /// follows the system unless overridden in Settings.
    var effectiveHighlightThemeID: String {
        if let id = settings.highlightTheme { return id }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark ? HighlightThemeCatalog.monokai.id : HighlightThemeCatalog.paper.id
    }

    private var settingsKey: String { "NoteIt.settings.v1" }
    private var snippetsKey: String { "NoteIt.snippets.v1" }
    private var recentsKey: String { "NoteIt.recents.v1" }
    private var enabledLangsKey: String { "NoteIt.enabledLangs.v1" }
    private var langPacksKey: String { "NoteIt.langPacks.v1" }
    private var sessionKey: String { "NoteIt.session.v1" }
    private var workspaceKey: String { "NoteIt.workspace.v1" }

    init() {
        loadPersistedState()
        if documents.isEmpty { newDocument() }
        saveSession()   // converge the session after a possible fresh start
        startAutosave()        // Persist settings/snippets/recents/packs/session on change
        $settings.sink { [weak self] s in self?.saveSettings(s) }.store(in: &cancellables)
        $snippets.sink { [weak self] s in self?.saveSnippets(s) }.store(in: &cancellables)
        $recentFiles.sink { [weak self] r in self?.saveRecents(r) }.store(in: &cancellables)
        $enabledLanguages.sink { [weak self] l in self?.saveEnabledLanguages(l) }.store(in: &cancellables)
        $languagePackSnippets.sink { [weak self] p in self?.saveLanguagePacks(p) }.store(in: &cancellables)
        // Session: save whenever the tab list or selection changes.
        // @Published publishers emit in willSet phase — reading self inside
        // a sink would see the pre-change state — so combine the *emitted*
        // values instead. dropFirst skips the initial current-value replay.
        $documents
            .combineLatest($selectedID)
            .dropFirst()
            .sink { [weak self] docs, id in self?.saveSession(documents: docs, selectedID: id) }
            .store(in: &cancellables)
    }

    // MARK: - Tabs
    func newDocument(text: String = "", fileURL: URL? = nil, isPreview: Bool = false) {
        let doc = EditorDocument(text: text, fileURL: fileURL, isPreview: isPreview)
        documents.append(doc)
        selectedID = doc.id
        trackDirtyState(of: doc)
    }

    func closeDocument(_ doc: EditorDocument) {
        docObservers.removeValue(forKey: doc.id)
        if let tv = textViews[doc.id] { syncFromTextView(tv, to: doc) }
        if doc.isDirty {
            let alert = NSAlert()
            alert.messageText = "Save changes to \"\(doc.title)\"?"
            alert.informativeText = "Your changes will be lost if you don't save."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                save(doc, saveAs: doc.fileURL == nil)
                if doc.isDirty { return } // save cancelled
            } else if resp == .alertThirdButtonReturn {
                return
            }
        }
        // Drop any autosave draft for this doc — don't leak "Untitled •" tabs.
        if let dir = autosaveDir() {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(doc.id.uuidString).txt"))
        }
        textViews.removeValue(forKey: doc.id)
        documents.removeAll { $0.id == doc.id }
        if placeholderSession?.docID == doc.id { placeholderSession = nil }
        if documents.isEmpty { newDocument() }
        if selectedID == doc.id { selectedID = documents.last?.id }
        pruneStaleDrafts()
    }

    func select(_ doc: EditorDocument) {
        selectedID = doc.id
        // A placeholder session belongs to the document it started in.
        if let s = placeholderSession, s.docID != doc.id { placeholderSession = nil }
    }

    // MARK: - Workspace

    func openWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to open as a workspace"
        if panel.runModal() == .OK, let url = panel.url {
            openWorkspace(url)
        }
    }

    func openWorkspace(_ url: URL) {
        workspace.open(url: url)
        UserDefaults.standard.set(url.path, forKey: workspaceKey)
    }

    func closeWorkspace() {
        workspace.close()
        UserDefaults.standard.removeObject(forKey: workspaceKey)
    }

    // MARK: - Preview / open from explorer

    /// Single click in the explorer: preview in a read-only tab. At most one
    /// preview tab exists at a time — it is reused for every preview.
    func openPreview(url: URL) {
        if let editing = documents.first(where: { !$0.isPreview && $0.fileURL == url }) {
            selectedID = editing.id   // already open for editing — just show it
            return
        }
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            NSSound.beep()
            return
        }
        if let preview = documents.first(where: { $0.isPreview }) {
            preview.text = s
            preview.fileURL = url
            preview.isDirty = false
            if let tv = textViews[preview.id] { tv.string = s }
            selectedID = preview.id
        } else {
            newDocument(text: s, fileURL: url, isPreview: true)
        }
    }

    /// Double click in the explorer: open for editing. A preview of the same
    /// file is promoted in place.
    func openForEditing(url: URL) {
        if let editing = documents.first(where: { !$0.isPreview && $0.fileURL == url }) {
            selectedID = editing.id
            pushRecent(url)
            return
        }
        if let preview = documents.first(where: { $0.isPreview && $0.fileURL == url }) {
            preview.isPreview = false
            selectedID = preview.id
            pushRecent(url)
            return
        }
        open(url: url)
    }

    /// Republishes a document's dirty state so explorer markers update.
    private func trackDirtyState(of doc: EditorDocument) {
        docObservers[doc.id] = doc.$isDirty
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - File IO
    func open() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")!, .init(filenameExtension: "swift")!, .init(filenameExtension: "txt")!]
        // Fallback: allow any text
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK {
            for url in panel.urls { open(url: url) }
        }
    }

    func open(url: URL) {
        if let existing = documents.first(where: { !$0.isPreview && $0.fileURL == url }) {
            selectedID = existing.id
            // reload from disk
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                existing.text = s
                existing.isDirty = false
                if let tv = textViews[existing.id] {
                    tv.string = s
                    existing.isDirty = false
                }
            }
            pushRecent(url)
            return
        }
        if let preview = documents.first(where: { $0.isPreview && $0.fileURL == url }) {
            // File ▸ Open on a previewed file promotes it to an editable tab.
            preview.isPreview = false
            selectedID = preview.id
            pushRecent(url)
            return
        }
        do {
            let s = try String(contentsOf: url, encoding: .utf8)
            // Reuse empty untitled tab
            if documents.count == 1, let only = documents.first,
               only.fileURL == nil, only.text.isEmpty, !only.isDirty, !only.isPreview {
                only.text = s; only.fileURL = url; only.isDirty = false
                if let tv = textViews[only.id] { tv.string = s; only.isDirty = false }
                selectedID = only.id
            } else {
                newDocument(text: s, fileURL: url)
                documents.last?.isDirty = false
            }
            pushRecent(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            NSSound.beep()
        }
    }

    func save(_ doc: EditorDocument, saveAs: Bool = false) {
        if let tv = textViews[doc.id] { syncFromTextView(tv, to: doc) }
        var url = doc.fileURL
        if saveAs || url == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = doc.fileURL?.lastPathComponent ?? "Untitled.txt"
            if panel.runModal() == .OK, let u = panel.url {
                url = u
            } else { return }
        }
        guard let url else { return }
        do {
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            doc.fileURL = url
            doc.isDirty = false
            pushRecent(url)
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            let a = NSAlert(error: error); a.runModal()
        }
    }

    func saveAll() { for d in documents where d.isDirty { save(d) } }

    func revert(_ doc: EditorDocument) {
        guard let url = doc.fileURL,
              let s = try? String(contentsOf: url, encoding: .utf8) else { return }
        doc.text = s; doc.isDirty = false
        textViews[doc.id]?.string = s
        doc.isDirty = false
    }

    // MARK: - Recents
    func pushRecent(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(15))
    }

    // MARK: - Autosave
    func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: max(2, settings.autoSaveInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autosaveTick() }
        }
    }

    func autosaveTick() {
        guard settings.autoSaveEnabled else { return }
        let fm = FileManager.default
        for doc in documents where doc.isDirty && !doc.isPreview {
            if let tv = textViews[doc.id] { syncFromTextView(tv, to: doc) }
            if let url = doc.fileURL {
                try? doc.text.write(to: url, atomically: true, encoding: .utf8)
                doc.isDirty = false
                // Don't leave a stale draft behind once it's been saved
                if let dir = autosaveDir() {
                    try? fm.removeItem(at: dir.appendingPathComponent("\(doc.id.uuidString).txt"))
                }
            } else {
                // Draft autosave so relaunch restores content.
                // Skip empty untitled docs — otherwise every launch leaks a draft.
                if doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                if let dir = autosaveDir() {
                    try? doc.text.write(to: dir.appendingPathComponent("\(doc.id.uuidString).txt"), atomically: true, encoding: .utf8)
                    // keep isDirty true (still untitled) but draft is safe
                }
            }
        }
        pruneStaleDrafts()
    }

    /// Remove drafts whose doc no longer exists or whose doc is now saved.
    func pruneStaleDrafts() {
        guard let dir = autosaveDir(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let liveIDs = Set(documents.map { $0.id.uuidString })
        for f in files where f.pathExtension == "txt" {
            let base = f.deletingPathExtension().lastPathComponent
            // If no live doc owns this draft, delete it (user closed without saving an empty doc,
            // or doc was saved and draft cleaned via autosaveTick but an old file remains).
            if !liveIDs.contains(base) {
                try? FileManager.default.removeItem(at: f)
            }
        }
    }

    func autosaveDir() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("NoteIt/Autosave", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - TextView sync
    func syncFromTextView(_ tv: NSTextView, to doc: EditorDocument) {
        let s = tv.string
        if doc.text != s { doc.text = s }
    }

    func registerTextView(_ tv: NSTextView, for id: UUID) { textViews[id] = tv }
    func unregisterTextView(for id: UUID) { textViews.removeValue(forKey: id) }

    // MARK: - Persistence
    private func loadPersistedState() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: settingsKey),
           let s = try? JSONDecoder().decode(AppSettings.self, from: d) {
            settings = s
        }
        if let d = ud.data(forKey: snippetsKey),
           let s = try? JSONDecoder().decode([TextSnippet].self, from: d) {
            snippets = s
        }
        if let arr = ud.array(forKey: recentsKey) as? [String] {
            recentFiles = arr.compactMap { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        if let arr = ud.stringArray(forKey: enabledLangsKey) {
            enabledLanguages = Set(arr.compactMap { Language(rawValue: $0) })
        }
        if let d = ud.data(forKey: langPacksKey),
           let packs = try? JSONDecoder().decode([String: [TextSnippet]].self, from: d) {
            languagePackSnippets = packs
        }
        // An enabled pack must always have storage; seed built-ins for any
        // pack that has none yet (e.g. defaults changed between releases).
        for lang in enabledLanguages where languagePackSnippets[lang.rawValue] == nil {
            languagePackSnippets[lang.rawValue] = lang.builtInSnippets
        }
        // Restore the tab session (open tabs + which one was selected).
        // Falls back to the legacy draft-only restore on the first launch
        // after upgrading (no session saved yet).
        if let d = ud.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(SessionState.self, from: d),
           !session.entries.isEmpty {
            restoreSession(session)
        } else {
            restoreDraftsByMtime()
        }
        // Restore the workspace folder (if it still exists).
        if let path = ud.string(forKey: workspaceKey),
           FileManager.default.fileExists(atPath: path) {
            workspace.open(url: URL(fileURLWithPath: path))
        }
    }

    /// Rebuilds the tab bar from the persisted session: file-backed tabs
    /// reopen from disk, untitled tabs return from their auto-save drafts,
    /// and the previously selected tab is selected again. Missing files and
    /// empty drafts are dropped.
    private func restoreSession(_ session: SessionState) {
        guard let dir = autosaveDir() else { return }
        var restored: [EditorDocument] = []
        for entry in session.entries {
            if let path = entry.filePath {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path),
                      let s = try? String(contentsOf: url, encoding: .utf8) else { continue }
                restored.append(EditorDocument(text: s, fileURL: url))
            } else if let draft = entry.draftFile {
                let src = dir.appendingPathComponent(draft)
                guard let s = try? String(contentsOf: src, encoding: .utf8),
                      !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    try? FileManager.default.removeItem(at: src)   // empty/corrupt draft
                    continue
                }
                let doc = EditorDocument(text: s)
                restored.append(doc)
                trackDirtyState(of: doc)
                doc.isDirty = true
                // Rename the draft to the new doc's id so autosave reuses the
                // same file and pruneStaleDrafts keeps owning it.
                try? FileManager.default.moveItem(at: src, to: dir.appendingPathComponent("\(doc.id.uuidString).txt"))
            }
        }
        documents = restored
        // The index shifts when entries were dropped; clamp to what exists.
        selectedID = restored.indices.contains(session.selectedIndex)
            ? restored[session.selectedIndex].id
            : restored.first?.id
        // The draft renames above changed names on disk — rewrite the
        // session so the *next* launch finds the new file names.
        saveSession()
        pruneStaleDrafts()
    }

    /// Legacy restore (no saved session yet): untitled drafts, oldest first.
    private func restoreDraftsByMtime() {
        guard let dir = autosaveDir(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        // Restore in mtime order so tab order is stable, cap to 20 so a
        // corrupted dir can't spawn hundreds of tabs.
        let sorted = files.filter { $0.pathExtension == "txt" }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a < b
        }.prefix(20)
        for f in sorted {
            if let s = try? String(contentsOf: f, encoding: .utf8),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let doc = EditorDocument(text: s)
                documents.append(doc)
                trackDirtyState(of: doc)
                doc.isDirty = true
                // Rename old draft file to the new doc's file so prune/cleanup
                // works and the next autosave overwrites the same file.
                try? FileManager.default.moveItem(at: f, to: dir.appendingPathComponent("\(doc.id.uuidString).txt"))
            } else {
                // Empty/corrupt draft — just delete it.
                try? FileManager.default.removeItem(at: f)
            }
        }
        // Any remaining txt files beyond the cap are stale leaks — delete.
        let remaining = files.filter { $0.pathExtension == "txt" }
        for f in remaining where !sorted.contains(f) {
            try? FileManager.default.removeItem(at: f)
        }
        // The restored tab used to display only through selectedDocument's
        // first-tab fallback while selectedID stayed nil — so no tab was
        // highlighted at launch. Select one for real.
        if selectedID == nil { selectedID = documents.first?.id }
    }

    private func saveSettings(_ s: AppSettings) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: settingsKey) }
    }
    private func saveSnippets(_ s: [TextSnippet]) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: snippetsKey) }
    }
    private func saveRecents(_ r: [URL]) {
        UserDefaults.standard.set(r.map { $0.path }, forKey: recentsKey)
    }

    private func saveEnabledLanguages(_ langs: Set<Language>) {
        UserDefaults.standard.set(Array(langs).map { $0.rawValue }, forKey: enabledLangsKey)
    }

    private func saveLanguagePacks(_ packs: [String: [TextSnippet]]) {
        if let d = try? JSONEncoder().encode(packs) { UserDefaults.standard.set(d, forKey: langPacksKey) }
    }

    /// Persists the open tabs (in order) and which one is selected, so the
    /// next launch restores the session exactly. Untitled tabs are identified
    /// by their draft file name — deterministic (`<doc-id>.txt`) even before
    /// the first auto-save writes it. Preview tabs are not part of sessions.
    private func saveSession(documents: [EditorDocument]? = nil, selectedID: UUID? = nil) {
        let docs = (documents ?? self.documents).filter { !$0.isPreview }
        let sel = selectedID ?? self.selectedID
        let entries = docs.map { doc -> SessionEntry in
            if let path = doc.fileURL?.path { return SessionEntry(filePath: path, draftFile: nil) }
            return SessionEntry(filePath: nil, draftFile: "\(doc.id.uuidString).txt")
        }
        let index = docs.firstIndex(where: { $0.id == sel }) ?? 0
        if let d = try? JSONEncoder().encode(SessionState(entries: entries, selectedIndex: index)) {
            UserDefaults.standard.set(d, forKey: sessionKey)
        }
    }

    // MARK: - Find / Replace engine
    func nsFindOptions() -> NSString.CompareOptions {
        var o: NSString.CompareOptions = []
        if !search.caseSensitive { o.insert(.caseInsensitive) }
        return o
    }

    func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        if search.useRegex {
            do {
                var opts: NSRegularExpression.Options = []
                if !search.caseSensitive { opts.insert(.caseInsensitive) }
                let re = try NSRegularExpression(pattern: query, options: opts)
                let ns = text as NSString
                return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { $0.range }
            } catch { return [] }
        } else {
            var out: [NSRange] = []
            let ns = text as NSString
            let opts = nsFindOptions()
            var searchRange = NSRange(location: 0, length: ns.length)
            while searchRange.location < ns.length {
                let r = ns.range(of: query, options: opts, range: searchRange)
                if r.location == NSNotFound { break }
                if search.wholeWord {
                    let beforeOK: Bool = {
                        if r.location == 0 { return true }
                        let c = ns.character(at: r.location - 1)
                        guard let sc = UnicodeScalar(c) else { return true }
                        return CharacterSet.alphanumerics.contains(sc) == false
                    }()
                    let afterOK: Bool = {
                        if NSMaxRange(r) >= ns.length { return true }
                        let c = ns.character(at: NSMaxRange(r))
                        guard let sc = UnicodeScalar(c) else { return true }
                        return CharacterSet.alphanumerics.contains(sc) == false
                    }()
                    if !(beforeOK && afterOK) {
                        searchRange = NSRange(location: r.location + 1, length: ns.length - r.location - 1)
                        continue
                    }
                }
                out.append(r)
                let next = r.location + max(1, r.length)
                if next >= ns.length { break }
                searchRange = NSRange(location: next, length: ns.length - next)
            }
            return out
        }
    }

    func findNext(wrap: Bool? = nil) {
        guard let doc = selectedDocument, let tv = textViews[doc.id] else { return }
        syncFromTextView(tv, to: doc)
        let rs = ranges(of: search.query, in: doc.text)
        guard !rs.isEmpty else { NSSound.beep(); return }
        let cur = tv.selectedRange().location
        let wrap = wrap ?? search.wrapAround
        if let nxt = rs.first(where: { $0.location > cur }) ?? (wrap ? rs.first : nil) {
            tv.setSelectedRange(nxt)
            tv.scrollRangeToVisible(nxt)
            tv.showFindIndicator(for: nxt)
        } else { NSSound.beep() }
    }

    func findPrevious() {
        guard let doc = selectedDocument, let tv = textViews[doc.id] else { return }
        syncFromTextView(tv, to: doc)
        let rs = ranges(of: search.query, in: doc.text)
        guard !rs.isEmpty else { NSSound.beep(); return }
        let cur = tv.selectedRange().location
        if let prv = rs.last(where: { $0.location < cur }) ?? (search.wrapAround ? rs.last : nil) {
            tv.setSelectedRange(prv)
            tv.scrollRangeToVisible(prv)
            tv.showFindIndicator(for: prv)
        } else { NSSound.beep() }
    }

    func replaceCurrent() {
        guard let doc = selectedDocument, let tv = textViews[doc.id] else { return }
        let sel = tv.selectedRange()
        let ns = doc.text as NSString
        guard sel.location != NSNotFound, NSMaxRange(sel) <= ns.length else { return }
        let selectedText = ns.substring(with: sel)
        let matches: Bool = {
            if search.useRegex {
                return (try? NSRegularExpression(pattern: search.query, options: search.caseSensitive ? [] : .caseInsensitive))
                    .map { $0.firstMatch(in: selectedText, range: NSRange(location: 0, length: (selectedText as NSString).length)) != nil } ?? false
            } else if search.caseSensitive { return selectedText == search.query }
            else { return selectedText.lowercased() == search.query.lowercased() }
        }()
        if matches {
            tv.shouldChangeText(in: sel, replacementString: search.replacement)
            tv.replaceCharacters(in: sel, with: search.replacement)
            tv.didChangeText()
            syncFromTextView(tv, to: doc)
        }
        findNext()
    }

    func replaceAll() {
        guard let doc = selectedDocument, let tv = textViews[doc.id], !search.query.isEmpty else { return }
        syncFromTextView(tv, to: doc)
        let original = doc.text
        var result: String
        if search.useRegex {
            do {
                let re = try NSRegularExpression(pattern: search.query, options: search.caseSensitive ? [] : .caseInsensitive)
                result = re.stringByReplacingMatches(in: original, range: NSRange(location: 0, length: (original as NSString).length), withTemplate: NSRegularExpression.escapedTemplate(for: search.replacement))
            } catch { NSSound.beep(); return }
        } else {
            let rs = ranges(of: search.query, in: original).reversed()
            guard !rs.isEmpty else { NSSound.beep(); return }
            let m = NSMutableString(string: original)
            for r in rs { m.replaceCharacters(in: r, with: search.replacement) }
            result = m as String
        }
        if result != original {
            tv.undoManager?.beginUndoGrouping()
            tv.string = result
            tv.undoManager?.endUndoGrouping()
            tv.didChangeText()
            syncFromTextView(tv, to: doc)
        }
    }

    func goToLine(_ line: Int) {
        guard let doc = selectedDocument, let tv = textViews[doc.id] else { return }
        syncFromTextView(tv, to: doc)
        let ns = doc.text as NSString
        var loc = 0, count = 1
        let target = max(1, line)
        while count < target {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
            if r.location == NSNotFound { NSSound.beep(); return }
            loc = r.location + 1
            count += 1
        }
        var len = 0
        let lineRange = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
        len = (lineRange.location == NSNotFound) ? ns.length - loc : lineRange.location - loc
        let range = NSRange(location: loc, length: len)
        tv.setSelectedRange(range)
        tv.scrollRangeToVisible(range)
        tv.showFindIndicator(for: range)
        // focus
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: - Language packs

    /// Includes or excludes a pack. Enabling seeds the pack with a private
    /// copy of the built-ins the first time; disabling keeps the stored
    /// snippets so re-enabling restores the user's edited set.
    func setLanguagePack(_ lang: Language, enabled: Bool) {
        if enabled {
            enabledLanguages.insert(lang)
            if languagePackSnippets[lang.rawValue] == nil {
                languagePackSnippets[lang.rawValue] = lang.builtInSnippets
            }
        } else {
            enabledLanguages.remove(lang)
        }
    }

    func snippets(for lang: Language) -> [TextSnippet] {
        languagePackSnippets[lang.rawValue] ?? []
    }

    func setSnippets(_ snippets: [TextSnippet], for lang: Language) {
        languagePackSnippets[lang.rawValue] = snippets
    }

    /// Snippets whose triggers are live for `doc`: the personal list plus the
    /// pack of the document's active language (when that pack is enabled).
    /// Triggers may repeat across packs — only one pack is ever in play, and
    /// personal snippets win on conflicts.
    func activeSnippets(for doc: EditorDocument?) -> [TextSnippet] {
        guard let lang = doc?.activeLanguage, enabledLanguages.contains(lang) else { return snippets }
        return snippets + snippets(for: lang)
    }

    // MARK: - Snippets
    func insertSnippet(_ snippet: TextSnippet) {
        guard let doc = selectedDocument, !doc.isPreview, let tv = textViews[doc.id] else {
            NSSound.beep()
            return
        }
        let expansion = snippet.resolvedExpansion()
        let sel = tv.selectedRange()
        tv.shouldChangeText(in: sel, replacementString: expansion)
        tv.replaceCharacters(in: sel, with: expansion)
        tv.didChangeText()
        // Select the first <#...#> so the user can type straight over it.
        startPlaceholderSession(docID: doc.id,
                                inserted: NSRange(location: sel.location,
                                                  length: (expansion as NSString).length),
                                in: tv)
        syncFromTextView(tv, to: doc)
        tv.window?.makeFirstResponder(tv)
    }

    func expandTriggerIfNeeded(in tv: NSTextView) -> Bool {
        // Tab-triggered snippet expansion: word before caret matches a trigger
        // in this document's active set (personal + active language pack)?
        let sel = tv.selectedRange()
        guard sel.length == 0, sel.location > 0 else { return false }
        let ns = tv.string as NSString
        let upto = min(sel.location, ns.length)
        let prefix = ns.substring(to: upto)
        let word = prefix.components(separatedBy: CharacterSet.whitespacesAndNewlines).last?
            .components(separatedBy: CharacterSet(charactersIn: "(){}[];,.\"'")).last ?? ""
        let doc = documents.first(where: { textViews[$0.id] === tv })
        guard !word.isEmpty,
              let snip = activeSnippets(for: doc).first(where: { $0.trigger == word }) else { return false }
        let range = NSRange(location: upto - (word as NSString).length, length: (word as NSString).length)
        let expansion = snip.resolvedExpansion()
        tv.shouldChangeText(in: range, replacementString: expansion)
        tv.replaceCharacters(in: range, with: expansion)
        tv.didChangeText()
        if let doc {
            startPlaceholderSession(docID: doc.id,
                                    inserted: NSRange(location: range.location,
                                                      length: (expansion as NSString).length),
                                    in: tv)
            syncFromTextView(tv, to: doc)
        }
        return true
    }

    // MARK: - Snippet placeholders

    /// A live placeholder-navigation session covering the text one snippet
    /// inserted.
    ///
    /// Scoped to the inserted range rather than the whole document on purpose:
    /// tokens are deliberately left in the text (never stripped), so a
    /// document-wide search would keep hijacking Tab for indentation forever
    /// in any file that still contains a stale `<#...#>`.
    private struct PlaceholderSession {
        let docID: UUID
        /// The inserted range, as it was at insertion time.
        let range: NSRange
        /// Document length at insertion time; used to grow the range when the
        /// user types a replacement longer than the token it replaced.
        let baseLength: Int
    }

    private static let tokenOpen = "<#"
    private static let tokenClose = "#>"

    /// All literal `<#...#>` tokens inside `range`. Re-scanned on every Tab
    /// rather than cached, so the list stays correct after the user types over
    /// a token (which removes it) or edits around them.
    private func placeholderRanges(in text: NSString, within range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        var search = range
        while search.length > 0 {
            let open = text.range(of: Self.tokenOpen, options: [], range: search)
            if open.location == NSNotFound { break }
            let rest = NSRange(location: open.upperBound,
                               length: max(0, search.upperBound - open.upperBound))
            let close = text.range(of: Self.tokenClose, options: [], range: rest)
            if close.location == NSNotFound { break }
            result.append(NSRange(location: open.location,
                                  length: close.upperBound - open.location))
            let next = close.upperBound
            search = NSRange(location: next, length: max(0, search.upperBound - next))
        }
        return result
    }

    /// Begins a session over `inserted` and selects its first token.
    /// Snippets with no tokens simply start no session.
    private func startPlaceholderSession(docID: UUID, inserted: NSRange, in tv: NSTextView) {
        let ns = tv.string as NSString
        let clamped = NSIntersectionRange(inserted, NSRange(location: 0, length: ns.length))
        guard let first = placeholderRanges(in: ns, within: clamped).first else {
            placeholderSession = nil
            return
        }
        placeholderSession = PlaceholderSession(docID: docID, range: clamped, baseLength: ns.length)
        tv.setSelectedRange(first)
        tv.scrollRangeToVisible(first)
    }

    /// Moves the selection to the next (`backwards == false`) or previous
    /// token in the active session.
    ///
    /// Returns true when it moved, meaning the key press is consumed. Returns
    /// false — and ends the session — when there is no further token, so Tab
    /// falls through to its normal behaviour (indent).
    @discardableResult
    func navigatePlaceholder(in tv: NSTextView, backwards: Bool) -> Bool {
        guard let session = placeholderSession,
              let doc = documents.first(where: { textViews[$0.id] === tv }),
              doc.id == session.docID else { return false }

        let ns = tv.string as NSString
        // Grow the tail by however much the document has grown since insertion,
        // so a long replacement doesn't push the final token out of range.
        let growth = max(0, ns.length - session.baseLength)
        let start = min(session.range.location, ns.length)
        let end = min(ns.length, session.range.upperBound + growth)
        let tokens = placeholderRanges(in: ns,
                                       within: NSRange(location: start, length: max(0, end - start)))

        let caret = tv.selectedRange()
        let target: NSRange? = {
            if backwards {
                return tokens.reversed().first { $0.upperBound <= caret.location }
            }
            guard let i = tokens.firstIndex(where: { $0.location >= caret.location }) else { return nil }
            // Sitting exactly on a token means "advance past it", not "re-select".
            // On the LAST token there is nothing to advance to, so return nil:
            // that ends the session and lets Tab fall through to a real indent
            // instead of trapping the caret on the final token forever.
            if NSEqualRanges(tokens[i], caret) {
                let next = tokens.index(after: i)
                return next < tokens.count ? tokens[next] : nil
            }
            return tokens[i]
        }()

        guard let t = target else {
            // Ran out of tokens: end the session so the key falls through to
            // its normal behaviour. Collapse the selection first (trailing edge
            // going forward, leading edge going back) so the fall-through Tab
            // indents *beside* the token instead of replacing it — the token
            // was selected automatically, so silently eating it would strip
            // text the user never chose to remove.
            if caret.length > 0 {
                let edge = backwards ? caret.location : caret.upperBound
                let collapsed = NSRange(location: edge, length: 0)
                tv.setSelectedRange(collapsed)
                tv.scrollRangeToVisible(collapsed)
                syncFromTextView(tv, to: doc)
            }
            placeholderSession = nil
            return false
        }
        tv.setSelectedRange(t)
        tv.scrollRangeToVisible(t)
        syncFromTextView(tv, to: doc)
        return true
    }

    /// Ends the active session (Esc). Returns true if one was active.
    @discardableResult
    func endPlaceholderSession() -> Bool {
        guard placeholderSession != nil else { return false }
        placeholderSession = nil
        return true
    }

    // MARK: - Export / Print
    func exportPDF(_ doc: EditorDocument) {
        guard let tv = textViews[doc.id] else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(doc.title).pdf"
        if panel.runModal() == .OK, let url = panel.url {
            // Render text view content to PDF
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 566, height: 800))
            view.string = doc.text
            view.font = tv.font
            let data = view.dataWithPDF(inside: view.bounds)
            try? data.write(to: url)
        }
    }

    func exportText(_ doc: EditorDocument) { save(doc, saveAs: true) }

    func printDocument(_ doc: EditorDocument) {
        guard let tv = textViews[doc.id] else { return }
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSMakeSize(595, 842)
        let op = NSPrintOperation(view: tv, printInfo: printInfo)
        op.run()
    }
}
