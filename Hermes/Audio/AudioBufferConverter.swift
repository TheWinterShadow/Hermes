@preconcurrency import AVFoundation

/// Converts audio buffers to the format WhisperKit expects: 16kHz mono Float32.
enum AudioBufferConverter {
    nonisolated(unsafe) static let whisperFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    /// Convert an arbitrary PCM buffer to 16kHz mono Float32.
    static func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: whisperFormat) else {
            return nil
        }

        let ratio = whisperFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: whisperFormat,
            frameCapacity: outputFrameCount
        ) else {
            return nil
        }

        var error: NSError?
        var inputConsumed = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            print("[AudioBufferConverter] Conversion error: \(error)")
            return nil
        }

        return outputBuffer
    }
}
