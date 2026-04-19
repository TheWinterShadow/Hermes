import SwiftData
import SwiftUI

/// The application entry point for Hermes.
///
/// Hermes is a menu-bar-only app (`LSUIElement=true` in Info.plist) — it has no dock icon
/// and no main window. The `Settings { EmptyView() }` scene is required because SwiftUI's
/// `App` protocol demands at least one `Scene`, but we don't need a settings window.
/// All UI is driven by `AppDelegate` (menu bar status item + floating overlay panel).
///
/// The `modelContainer` modifier injects the shared SwiftData container into the
/// environment so any SwiftUI view (e.g., `SessionListView`) can use `@Query` and
/// `@Environment(\.modelContext)` to access persisted meeting sessions.
@main
struct HermesApp: App {
    /// Bridges to `AppDelegate` for AppKit-level setup (menu bar, overlay panel, audio capture).
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only — no main window. Settings scene is a no-op placeholder
        // required by the App protocol.
        Settings {
            EmptyView()
        }
        .modelContainer(TranscriptStore.shared.container)
    }
}
