import SwiftUI
import AppKit

// MARK: - Model

/// One entry in the explorer tree (file or folder), identified by its URL.
struct FileItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool { url.hasDirectoryPath }
}

/// Owns the open workspace folder and its (lazily loaded) tree.
/// Sidebar-styled SwiftUI lists pick up the app appearance (Light/Dark/
/// System) automatically — no extra theming needed here.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    /// Children per directory URL; absent = not loaded yet.
    @Published private(set) var children: [URL: [FileItem]] = [:]
    @Published private(set) var expanded: Set<URL> = []

    var isOpen: Bool { rootURL != nil }
    var rootName: String { rootURL?.lastPathComponent ?? "" }

    // MARK: Lifecycle

    func open(url: URL) {
        guard url.hasDirectoryPath else { return }
        rootURL = url
        children.removeAll()
        expanded = []
        load(url)
    }

    func close() {
        rootURL = nil
        children.removeAll()
        expanded = []
    }

    /// Re-reads every loaded folder (context-menu Refresh).
    func reload() {
        guard let root = rootURL else { return }
        let wasExpanded = expanded
        children.removeAll()
        expanded = []
        load(root)
        for url in wasExpanded { setExpanded(url, true) }
    }

    // MARK: Tree access

    func items(in directory: URL) -> [FileItem] {
        children[directory] ?? []
    }

    func isExpanded(_ url: URL) -> Bool {
        expanded.contains(url)
    }

    func setExpanded(_ url: URL, _ open: Bool) {
        if open {
            expanded.insert(url)
            if children[url] == nil { load(url) }
        } else {
            expanded.remove(url)
        }
    }

    /// True when `url` is an ancestor of `possibleDescendant` (used to keep
    /// empty folders distinguishable from unloaded ones).
    func isDescendant(_ possibleDescendant: URL, of url: URL) -> Bool {
        possibleDescendant.path.hasPrefix(url.path + "/")
    }

    // MARK: Loading

    private func load(_ directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles])
        else {
            children[directory] = []
            return
        }
        let items = contents.map { FileItem(url: $0) }
            .sorted {
                switch ($0.isDirectory, $1.isDirectory) {
                case (true, false): return true
                case (false, true): return false
                default: return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        children[directory] = items
    }
}

// MARK: - Explorer pane

/// The collapsible left pane: workspace folder tree. Single click previews a
/// file (reused read-only tab); double click opens it for editing. Files
/// with unsaved changes are shown in green.
struct WorkspaceExplorer: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            if workspace.isOpen {
                header
                Divider()
                List {
                    FolderContent(store: store, workspace: workspace, dir: workspace.rootURL!)
                }
                .listStyle(.sidebar)
            } else {
                emptyState
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            Text(workspace.rootName)
                .font(.callout.weight(.semibold))
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(action: { workspace.reload() }) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Refresh the file list")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .contextMenu {
            Button("Open Folder…") {
                NotificationCenter.default.post(name: .noteItOpenFolder, object: nil)
            }
            Divider()
            Button("Close Workspace") {
                NotificationCenter.default.post(name: .noteItCloseWorkspace, object: nil)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No Workspace")
                .font(.headline)
            Text("Open a folder to browse and preview its files here.")
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

/// Recursive folder rows. Children load lazily on first expansion.
private struct FolderContent: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var workspace: WorkspaceStore
    let dir: URL

    var body: some View {
        ForEach(workspace.items(in: dir)) { item in
            if item.isDirectory {
                DisclosureGroup(isExpanded: expansion(item.url)) {
                    FolderContent(store: store, workspace: workspace, dir: item.url)
                } label: {
                    FolderRow(name: item.name, isDirectory: true, isDirty: false, isSelected: false)
                }
            } else {
                FileRow(store: store, item: item)
            }
        }
    }

    private func expansion(_ url: URL) -> Binding<Bool> {
        Binding(
            get: { workspace.isExpanded(url) },
            set: { workspace.setExpanded(url, $0) }
        )
    }
}

private struct FileRow: View {
    @ObservedObject var store: DocumentStore
    let item: FileItem

    /// The editor tab this file belongs to, if any (drives selection +
    /// unsaved coloring).
    private var owningDoc: EditorDocument? {
        store.documents.first { $0.fileURL == item.url }
    }

    var body: some View {
        let doc = owningDoc
        let dirty = doc.map { !$0.isPreview && $0.isDirty } ?? false
        let selected = store.selectedID == doc?.id

        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(dirty ? Color.green : Color.secondary)
            Text(item.name)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if dirty {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        }
        .foregroundStyle(dirty ? Color.green : (selected ? Color.accentColor : Color.primary))
        .contentShape(Rectangle())
        // Double first: a double click also fires the single-tap preview,
        // then promotes it — the same flow editors use.
        .onTapGesture(count: 2) { store.openForEditing(url: item.url) }
        .onTapGesture(count: 1) { store.openPreview(url: item.url) }
        .contextMenu {
            Button("Open") { store.openForEditing(url: item.url) }
            Button("Preview") { store.openPreview(url: item.url) }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
    }
}

private struct FolderRow: View {
    let name: String
    let isDirectory: Bool
    let isDirty: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.callout)
                .foregroundStyle(.tint)
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}
