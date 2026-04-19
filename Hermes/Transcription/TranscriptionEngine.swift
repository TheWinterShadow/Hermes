import Foundation
@preconcurrency import WhisperKit

/// Wraps WhisperKit for transcription of audio buffers.
/// Handles model loading and transcription of raw Float32 audio samples.
actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private(set) var isReady = false

    /// Load the WhisperKit model. Call once at app startup.
    func loadModel() async throws {
        print("[TranscriptionEngine] Loading WhisperKit model...")

        // nil model = auto-select best model for this device
        // On M5 Max this will pick a large-v3 variant
        let config = WhisperKitConfig(
            model: "large-v3-v20240930_626MB",
            verbose: true,
            prewarm: true,
            load: true
        )
        whisperKit = try await WhisperKit(config)
        isReady = true

        print("[TranscriptionEngine] Model loaded and ready.")
    }

    /// Transcribe a buffer of raw Float32 audio samples.
    ///
    /// Samples must be 16kHz mono (resampled by `TranscriptionCoordinator` before calling).
    /// Uses English-only mode for faster inference. Results are mapped from WhisperKit's
    /// segment type to our `TranscriptSegment`, with special tokens stripped.
    ///
    /// - Parameters:
    ///   - samples: Raw Float32 audio at 16kHz sample rate.
    ///   - speaker: Which channel produced this audio (`.me` or `.them`).
    /// - Returns: Array of transcript segments, filtered to exclude empty text.
    /// - Throws: `TranscriptionError.modelNotLoaded` if called before `loadModel()`.
    func transcribe(samples: [Float], speaker: Speaker) async throws -> [TranscriptSegment] {
        guard let whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !samples.isEmpty else { return [] }

        // DecodingOptions: verbose=false suppresses per-token logging, task=.transcribe
        // (not .translate), language="en" forces English-only mode for lower latency.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en"
        )

        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )

        // Convert WhisperKit segments to our TranscriptSegment type
        return results.flatMap { result in
            result.segments.map { seg in
                TranscriptSegment(
                    speaker: speaker,
                    text: Self.stripSpecialTokens(seg.text),
                    startTime: TimeInterval(seg.start),
                    endTime: TimeInterval(seg.end)
                )
            }
        }
        .filter { !$0.text.isEmpty }
    }

    /// Remove WhisperKit special tokens that leak into transcript text.
    /// Tokens look like: <|startoftranscript|>, <|en|>, <|0.00|>, <|endoftext|>, <|transcribe|>, etc.
    private static func stripSpecialTokens(_ text: String) -> String {
        text.replacing(/\<\|[^|]*\|>/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: "WhisperKit model not loaded. Call loadModel() first."
        }
    }
}
