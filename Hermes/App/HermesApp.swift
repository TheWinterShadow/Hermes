import SwiftData
import SwiftUI

@main
struct HermesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only — no main window
        Settings {
            EmptyView()
        }
        .modelContainer(TranscriptStore.shared.container)
    }
}
