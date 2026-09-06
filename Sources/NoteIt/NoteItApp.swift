import SwiftUI
import AppKit

@main
struct NoteItApp: App {
    @StateObject private var store = DocumentStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear {
                    // REQUIRED for `swift run`: a raw SwiftPM binary has no
                    // .app bundle, so the process starts with activation
                    // policy .prohibited (no dock icon, no windows, can't
                    // activate). Promote to a regular foreground app.
                    // Harmless when already bundled as NoteIt.app.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    applyAppearance()
                }
                .onChange(of: store.settings.appearance) { _ in applyAppearance() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            NoteItCommands(appStore: store)
        }
    }

    /// Appearance is applied at the NSApp level rather than through
    /// SwiftUI's `preferredColorScheme`: when that modifier transitions from
    /// a concrete scheme back to nil (Light → System while the system is
    /// dark), the tab bar and the AppKit text view stay stuck in the old
    /// look. `NSApp.appearance` is a single source of truth that both
    /// SwiftUI's environment and AppKit-backed views follow on every
    /// transition — nil simply follows the system again.
    private func applyAppearance() {
        NSApp.appearance = switch store.settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .vibrantLight)
        case .dark: NSAppearance(named: .vibrantDark)
        }
    }
}
