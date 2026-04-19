import Foundation

/// A single segment of transcribed speech from one speaker.
///
/// Segments are the atomic unit of transcript data. Each represents one continuous
/// utterance from a single speaker as identified by WhisperKit. Segments are persisted
/// as JSON-encoded arrays inside `MeetingSession.segmentsData`.
struct TranscriptSegment: Identifiable, Codable, Sendable {
    /// Unique identifier for this segment.
    let id: UUID

    /// Who spoke this segment — `.me` (microphone) or `.them` (system audio).
    let speaker: Speaker

    /// The transcribed text with WhisperKit special tokens already stripped.
    let text: String

    /// Offset (in seconds) from the start of the transcription window where this segment begins.
    let startTime: TimeInterval

    /// Offset (in seconds) from the start of the transcription window where this segment ends.
    let endTime: TimeInterval

    /// Wall-clock time when this segment was created.
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
