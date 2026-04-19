import Foundation
import SwiftData

/// A recorded meeting session containing transcript segments.
@Model
final class MeetingSession {
    var title: String
    var startDate: Date
    var endDate: Date?
    var segmentsData: Data  // JSON-encoded [TranscriptSegment]

    init(title: String = "", startDate: Date = Date()) {
        self.title = title
        self.startDate = startDate
        self.endDate = nil
        self.segmentsData = Data()
    }

    // MARK: - Segment Access

    var segments: [TranscriptSegment] {
        get {
            (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
        }
        set {
            segmentsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

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
