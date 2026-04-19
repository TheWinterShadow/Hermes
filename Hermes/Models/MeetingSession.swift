import Foundation
import SwiftData

/// A recorded meeting session containing transcript segments.
///
/// Persisted via SwiftData. Segments are stored as a JSON-encoded `Data` blob
/// (`segmentsData`) rather than a SwiftData relationship because `TranscriptSegment`
/// is a simple value type and doesn't warrant its own model table.
@Model
final class MeetingSession {
    /// Display name for the session. Defaults to empty; the UI falls back to the formatted date.
    var title: String

    /// When the recording started.
    var startDate: Date

    /// When the recording stopped. `nil` while recording is in progress.
    var endDate: Date?

    /// JSON-encoded `[TranscriptSegment]`. Use the `segments` computed property for typed access.
    var segmentsData: Data  // JSON-encoded [TranscriptSegment]

    init(title: String = "", startDate: Date = Date()) {
        self.title = title
        self.startDate = startDate
        self.endDate = nil
        self.segmentsData = Data()
    }

    // MARK: - Segment Access

    /// Typed access to the transcript segments.
    ///
    /// The getter decodes `segmentsData` from JSON; the setter encodes back to JSON.
    /// Returns an empty array if decoding fails (e.g., empty data on a new session).
    var segments: [TranscriptSegment] {
        get {
            (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
        }
        set {
            segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    /// Appends a single segment to the session's transcript.
    ///
    /// This round-trips through JSON decode → append → encode. Acceptable for the
    /// low frequency of transcription events (~1 per 10 seconds per channel).
    ///
    /// - Parameter segment: The new transcript segment to persist.
    func appendSegment(_ segment: TranscriptSegment) {
        var current = segments
        current.append(segment)
        segments = current
    }

    /// Human-readable duration.
    var duration: String {
        guard let end = endDate else { return "In progress" }
        let interval = end.timeIntervalSince(startDate)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
