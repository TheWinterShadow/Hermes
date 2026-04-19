import AVFoundation
import Foundation

/// Coordinates audio buffering and transcription output.
/// Buffers incoming audio samples, resamples to 16kHz for WhisperKit,
/// and publishes transcript lines for the overlay UI.
@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published var lines: [TranscriptLine] = []
    @Published var isActive = false
    @Published var modelLoaded = false

    /// Incremented every time transcript content changes (new line or appended text).
    /// Used to trigger scroll-to-bottom in the overlay.
    @Published var scrollTrigger: Int = 0

    /// All segments produced during this recording — used for persistence.
    private(set) var allSegments: [TranscriptSegment] = []

    private let engine = TranscriptionEngine()

    // Audio buffers — accumulate samples until we have enough for a transcription window
    private var meSamples: [Float] = []
    private var themSamples: [Float] = []
    private var meSampleRate: Double = 48000
    private var themSampleRate: Double = 48000

    /// Minimum duration (seconds) before triggering transcription.
    /// 10s gives WhisperKit enough context for clean sentence boundaries.
    private let windowDuration: Double = 10.0

    /// Load the WhisperKit model at startup.
    func loadModel() async {
        do {
            try await engine.loadModel()
            modelLoaded = true
            print("[Coordinator] WhisperKit model loaded.")
        } catch {
            print("[Coordinator] Failed to load model: \(error)")
        }
    }

    /// Set the sample rate for a given speaker channel.
    func setSampleRate(_ rate: Double, for speaker: Speaker) {
        switch speaker {
        case .me: meSampleRate = rate
        case .them: themSampleRate = rate
        }
    }

    // Diagnostic counters
    private var meChunkCount = 0
    private var themChunkCount = 0

    /// Append incoming audio samples to the appropriate channel buffer.
    ///
    /// When a channel's buffer reaches `windowDuration` seconds of audio, it's drained
    /// and dispatched to `transcribeBuffer()` as an async task. This means both channels
    /// can be transcribed concurrently — the `.me` and `.them` buffers are independent.
    ///
    /// - Parameters:
    ///   - samples: Raw Float32 audio samples from the capture pipeline.
    ///   - speaker: Which channel produced these samples.
    func appendSamples(_ samples: [Float], from speaker: Speaker) {
        let sampleRate: Double
        switch speaker {
        case .me:
            meChunkCount += 1
            if meChunkCount % 100 == 1 {
                let rms = Self.rms(samples)
                print("[Coordinator] .me chunk #\(meChunkCount): \(samples.count) samples, RMS=\(String(format: "%.6f", rms)), buffer=\(meSamples.count)")
            }
            meSamples.append(contentsOf: samples)
            sampleRate = meSampleRate
            if Double(meSamples.count) / sampleRate >= windowDuration {
                let buffer = meSamples
                meSamples.removeAll(keepingCapacity: true)
                Task { await transcribeBuffer(buffer, speaker: .me, sampleRate: sampleRate) }
            }
        case .them:
            themChunkCount += 1
            if themChunkCount % 100 == 1 {
                let rms = Self.rms(samples)
                print("[Coordinator] .them chunk #\(themChunkCount): \(samples.count) samples, RMS=\(String(format: "%.6f", rms)), buffer=\(themSamples.count)")
            }
            themSamples.append(contentsOf: samples)
            sampleRate = themSampleRate
            if Double(themSamples.count) / sampleRate >= windowDuration {
                let buffer = themSamples
                themSamples.removeAll(keepingCapacity: true)
                Task { await transcribeBuffer(buffer, speaker: .them, sampleRate: sampleRate) }
            }
        }
    }

    /// Compute RMS (root mean square) of audio samples — used for silence detection.
    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    /// Flush any remaining samples (called when recording stops).
    func flush() {
        if !meSamples.isEmpty {
            let buffer = meSamples
            meSamples.removeAll()
            Task { await transcribeBuffer(buffer, speaker: .me, sampleRate: meSampleRate) }
        }
        if !themSamples.isEmpty {
            let buffer = themSamples
            themSamples.removeAll()
            Task { await transcribeBuffer(buffer, speaker: .them, sampleRate: themSampleRate) }
        }
    }

    /// Minimum RMS threshold to trigger transcription.
    /// Below this, audio is silence (or near-silence) and WhisperKit will hallucinate
    /// ("Thank you", "Thanks for watching", etc.). Skip it.
    private let silenceRMSThreshold: Float = 0.001

    /// Transcribe a drained audio buffer and publish results to the UI.
    ///
    /// Pipeline: silence gate → resample to 16kHz → WhisperKit transcription → merge
    /// into speaker turns. The silence gate (RMS < 0.001) prevents WhisperKit from
    /// hallucinating common phrases ("Thank you", "Thanks for watching") on silent buffers.
    ///
    /// Consecutive segments from the same speaker are merged into a single `TranscriptLine`
    /// to produce natural-looking continuous speaker turns.
    private func transcribeBuffer(_ samples: [Float], speaker: Speaker, sampleRate: Double) async {
        let duration = Double(samples.count) / sampleRate
        let rms = Self.rms(samples)
        print("[Coordinator] Transcribing \(speaker == .me ? ".me" : ".them") buffer: \(String(format: "%.1f", duration))s, \(samples.count) samples, RMS=\(String(format: "%.6f", rms))")

        // Silence gate — skip transcription for silent buffers to avoid hallucinations
        if rms < silenceRMSThreshold {
            print("[Coordinator] Skipping \(speaker == .me ? ".me" : ".them") — below silence threshold (\(silenceRMSThreshold))")
            return
        }

        guard modelLoaded else {
            // Model not ready yet — show placeholder
            let duration = Double(samples.count) / sampleRate
            let line = TranscriptLine(
                speaker: speaker,
                text: "[Audio: \(String(format: "%.1f", duration))s — model loading...]",
                timestamp: Date()
            )
            lines.append(line)
            return
        }

        // Resample to 16kHz if needed
        let resampled: [Float]
        if abs(sampleRate - 16000) < 1 {
            resampled = samples
        } else {
            resampled = resampleTo16kHz(samples, from: sampleRate)
        }

        do {
            let segments = try await engine.transcribe(samples: resampled, speaker: speaker)
            for segment in segments {
                allSegments.append(segment)

                // Merge into existing turn if same speaker, otherwise start new line
                if let lastLine = lines.last, lastLine.speaker == segment.speaker {
                    lastLine.append(segment.text)
                } else {
                    let line = TranscriptLine(
                        speaker: segment.speaker,
                        text: segment.text,
                        timestamp: segment.timestamp
                    )
                    lines.append(line)
                }
                scrollTrigger += 1
            }
            isActive = true
        } catch {
            print("[Coordinator] Transcription error: \(error)")
        }
    }

    /// Simple linear interpolation resampling to 16kHz.
    ///
    /// WhisperKit requires 16kHz mono Float32 input. CATap system audio comes in at
    /// 48kHz (or whatever the output device uses), and the mic may be at 44.1kHz or 48kHz.
    /// This is a basic lerp resampler — not production-quality for music, but perfectly
    /// adequate for speech transcription.
    private func resampleTo16kHz(_ samples: [Float], from sourceSampleRate: Double) -> [Float] {
        let ratio = 16000.0 / sourceSampleRate
        let outputCount = Int(Double(samples.count) * ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let srcIndex = Double(i) / ratio
            let index0 = Int(srcIndex)
            let fraction = Float(srcIndex - Double(index0))

            let s0 = samples[min(index0, samples.count - 1)]
            let s1 = samples[min(index0 + 1, samples.count - 1)]
            output[i] = s0 + fraction * (s1 - s0)
        }
        return output
    }

    /// Reset all state for a new recording session.
    ///
    /// Called by `AppDelegate` when starting a new recording. Clears all buffers,
    /// transcript lines, and persisted segments.
    func reset() {
        lines.removeAll()
        meSamples.removeAll()
        themSamples.removeAll()
        allSegments.removeAll()
        scrollTrigger = 0
        isActive = false
    }
}
