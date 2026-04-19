import Foundation
import SwiftData

/// Manages SwiftData persistence for meeting sessions.
///
/// Singleton that creates and owns the `ModelContainer`. The container is injected into
/// the SwiftUI environment via `.modelContainer()` in `HermesApp`, and also used directly
/// by `AppDelegate` when saving sessions outside of SwiftUI views.
///
/// Marked `@unchecked Sendable` because the `ModelContainer` itself is thread-safe and
/// this class is effectively immutable after init.
final class TranscriptStore: @unchecked Sendable {
    static let shared = TranscriptStore()

    /// The SwiftData model container backed by on-disk SQLite.
    let container: ModelContainer

    /// Creates the model container for `MeetingSession`.
    ///
    /// Uses a named configuration ("Hermes") so the SQLite file lands at
    /// `~/Library/Application Support/Hermes/Hermes.store`.
    /// Crashes with `fatalError` if the container can't be created — this is intentional
    /// because the app can't function without persistence.
    private init() {
        let schema = Schema([MeetingSession.self])
        let config = ModelConfiguration(
            "Hermes",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("[TranscriptStore] Failed to create ModelContainer: \(error)")
        }
    }
}
