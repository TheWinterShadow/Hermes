import Foundation
import SwiftData

/// Manages SwiftData persistence for meeting sessions.
final class TranscriptStore: @unchecked Sendable {
    static let shared = TranscriptStore()

    let container: ModelContainer

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
