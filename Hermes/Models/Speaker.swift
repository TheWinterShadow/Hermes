import Foundation

/// Identifies which side of the conversation a transcript segment belongs to.
enum Speaker: String, Codable, Sendable {
    /// The local user (captured via microphone).
    case me
    /// Remote participants (captured via system audio / CATap).
    case them
}
