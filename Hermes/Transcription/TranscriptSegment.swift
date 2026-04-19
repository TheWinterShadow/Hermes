import Foundation

/// A single segment of transcribed speech.
struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let speaker: Speaker
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let timestamp: Date

    init(
        id: UUID = UUID(),
        speaker: Speaker,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.timestamp = timestamp
    }
}
