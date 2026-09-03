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
                .preferredColorScheme(colorScheme)
                .onAppear {
                    // REQUIRED for `swift run`: a raw SwiftPM binary has no
                    // .app bundle, so the process starts with activation
                    // policy .prohibited (no dock icon, no windows, can't
                    // activate). Promote to a regular foreground app.
                    // Harmless when already bundled as NoteIt.app.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            NoteItCommands(appStore: store)
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
