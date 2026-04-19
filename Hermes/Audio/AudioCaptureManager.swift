import AVFoundation
import CoreAudio

/// Stashed pointer to the AudioCaptureManager's callback for use by the C IOProc.
/// Set before AudioDeviceStart, read on the real-time audio thread.
private nonisolated(unsafe) var gSystemAudioCallback: (([Float], Speaker) -> Void)?

/// When true, the IOProc skips forwarding audio samples (pause state).
private nonisolated(unsafe) var gSystemAudioPaused = false

/// C-compatible IOProc for the aggregate device.
/// Runs on the real-time audio IO thread — no allocations, no locks, no ObjC.
/// We break that rule slightly by creating a Swift Array, which is acceptable
/// for a transcription app (not pro audio).
private func systemAudioIOProc(
    _ inDevice: AudioObjectID,
    _: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    outOutputData: UnsafeMutablePointer<AudioBufferList>,
    _: UnsafePointer<AudioTimeStamp>,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    let bufferList = UnsafeMutableAudioBufferListPointer(
        UnsafeMutablePointer(mutating: inInputData))

    guard let firstBuffer = bufferList.first,
          let data = firstBuffer.mData else {
        return noErr
    }

    let frameCount = Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size
    guard frameCount > 0 else { return noErr }

    let floatPointer = data.assumingMemoryBound(to: Float.self)
    let samples = Array(UnsafeBufferPointer(start: floatPointer, count: frameCount))

    if !gSystemAudioPaused {
        gSystemAudioCallback?(samples, .them)
    }
    return noErr
}

/// Manages dual audio capture:
/// - System audio via CATap + Aggregate Device + IOProc (low-level Core Audio)
/// - Microphone via AVAudioEngine
///
/// NOT MainActor-isolated — audio APIs have their own threading requirements.
final class AudioCaptureManager: @unchecked Sendable {
    private(set) var isCapturing = false
    private(set) var isPaused = false

    // System audio (CATap)
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?

    // Microphone
    private var micEngine: AVAudioEngine?

    /// The input device ID to use for mic capture. nil = system default.
    var micDeviceID: AudioDeviceID?

    /// Called when new audio samples are available from background audio threads.
    var onAudioSamples: (@Sendable ([Float], Speaker) -> Void)?

    // MARK: - Start / Stop / Pause

    /// Start both system audio (CATap) and microphone (AVAudioEngine) capture.
    /// - Throws: `AudioCaptureError` if CATap or mic setup fails.
    func startCapture() throws {
        guard !isCapturing else { return }

        try setupSystemAudioTap()
        try setupMicCapture()

        isCapturing = true
        isPaused = false
    }

    /// Stop all capture. Cleanup order matters:
    /// stop device → destroy IO proc → destroy aggregate device → destroy process tap.
    func stopCapture() {
        tearDownMicCapture()
        tearDownSystemAudioTap()
        isCapturing = false
        isPaused = false
        gSystemAudioPaused = false
    }

    /// Pause capture: stop mic engine and suppress system audio IOProc forwarding.
    func pauseCapture() {
        guard isCapturing, !isPaused else { return }
        micEngine?.pause()
        gSystemAudioPaused = true
        isPaused = true
        print("[AudioCapture] Paused.")
    }

    /// Resume capture after a pause.
    func resumeCapture() {
        guard isCapturing, isPaused else { return }
        gSystemAudioPaused = false
        try? micEngine?.start()
        isPaused = false
        print("[AudioCapture] Resumed.")
    }

    // MARK: - System Audio (CATap)

    /// Set up the full CATap pipeline for capturing all system audio.
    ///
    /// Steps:
    /// 1. Create a `CATapDescription` process tap (macOS 14.2+) targeting all system audio.
    /// 2. Create a private aggregate device (empty sub-device list, two-phase pattern).
    /// 3. Attach the tap to the aggregate device post-creation via property set.
    /// 4. Register a C-function-pointer IOProc and start the device.
    ///
    /// Key insight: `isExclusive = true` with empty `processes` means "the process list
    /// is an exclusion list" — exclude nothing = capture everything. `isExclusive = false`
    /// with empty processes would capture nothing (zero-filled buffers).
    ///
    /// - Throws: `AudioCaptureError` at each step if Core Audio returns an error status.
    private func setupSystemAudioTap() throws {
        // 1. Create a system-wide process tap (empty processes = all system audio)
        let tapDescription = CATapDescription()
        tapDescription.name = "hermes-system-tap"
        tapDescription.processes = []
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .unmuted
        tapDescription.isMixdown = true
        tapDescription.isMono = true
        tapDescription.isExclusive = true  // empty processes + exclusive = "exclude nothing" = capture all

        var localTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &localTapID)
        guard status == noErr else {
            throw AudioCaptureError.tapCreationFailed(status)
        }
        self.tapID = localTapID
        print("[AudioCapture] Process tap created: \(localTapID)")

        // Read the tap's UID for later attachment
        let tapUID = try readTapUID(tapID: localTapID)
        print("[AudioCapture] Tap UID: \(tapUID)")

        // 2. Create aggregate device with EMPTY sub-device list and NO tap list.
        //    Two-phase approach (audiotee pattern): create first, attach tap after.
        //    This avoids -10877 (kAudioUnitErr_NoConnection) errors from trying to
        //    wire the tap during creation.
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: "Hermes-Aggregate",
            kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
            kAudioAggregateDeviceSubDeviceListKey as String: [] as [Any],
            kAudioAggregateDeviceMasterSubDeviceKey as String: 0,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
        ]

        var localAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDescription as CFDictionary, &localAggregateID)
        guard status == noErr else {
            throw AudioCaptureError.aggregateDeviceFailed(status)
        }
        self.aggregateDeviceID = localAggregateID
        print("[AudioCapture] Aggregate device created: \(localAggregateID)")

        // 3. Attach the tap to the aggregate device via property set (post-creation).
        try attachTapToAggregateDevice(
            aggregateID: localAggregateID, tapUID: tapUID)
        print("[AudioCapture] Tap attached to aggregate device")

        // Read the stream format from the tap
        let format = try readTapFormat(tapID: localTapID)

        // 4. Set up the C-function-pointer IOProc and start the device.
        gSystemAudioCallback = self.onAudioSamples

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcID(
            localAggregateID,
            systemAudioIOProc,
            nil,
            &procID
        )
        guard let procID, status == noErr else {
            throw AudioCaptureError.ioProcFailed(status)
        }
        self.deviceProcID = procID

        status = AudioDeviceStart(localAggregateID, procID)
        guard status == noErr else {
            throw AudioCaptureError.deviceStartFailed(status)
        }

        print("[AudioCapture] System audio tap started. Format: \(format)")
    }

    /// Attach a process tap to an existing aggregate device by setting
    /// `kAudioAggregateDevicePropertyTapList` after creation.
    ///
    /// This two-phase approach (create aggregate, then attach tap) avoids `-10877`
    /// (`kAudioUnitErr_NoConnection`) errors that occur when trying to wire the tap
    /// during aggregate device creation.
    ///
    /// - Parameters:
    ///   - aggregateID: The aggregate device to attach the tap to.
    ///   - tapUID: The UID string of the process tap to attach.
    /// - Throws: `AudioCaptureError.propertyReadFailed` if the property set fails.
    private func attachTapToAggregateDevice(
        aggregateID: AudioObjectID, tapUID: String
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyTapList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapArray = [tapUID as CFString] as CFArray
        let size = UInt32(MemoryLayout<CFArray>.size)

        let status = AudioObjectSetPropertyData(
            aggregateID, &address, 0, nil, size, &tapArray
        )
        guard status == noErr else {
            throw AudioCaptureError.propertyReadFailed(status)
        }
    }

    /// Tear down system audio capture in the correct order to avoid crashes.
    /// Order: stop device → destroy IO proc → destroy aggregate device → destroy process tap.
    private func tearDownSystemAudioTap() {
        if let procID = deviceProcID, aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }

        gSystemAudioCallback = nil
        deviceProcID = nil
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)

        print("[AudioCapture] System audio tap stopped.")
    }

    // MARK: - Microphone (AVAudioEngine)

    /// Set up microphone capture using AVAudioEngine.
    ///
    /// If `micDeviceID` is set, points the engine's input node at that device
    /// via `kAudioOutputUnitProperty_CurrentDevice`. Otherwise uses the system default.
    /// Installs a tap on bus 0 that forwards raw Float32 samples to `onAudioSamples`.
    ///
    /// - Throws: If `AVAudioEngine.start()` fails.
    private func setupMicCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        // Point AVAudioEngine at the selected input device (if set)
        if let deviceID = micDeviceID {
            var id = deviceID
            let status = AudioUnitSetProperty(
                inputNode.audioUnit!,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &id,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                print("[AudioCapture] Warning: failed to set mic device \(deviceID), OSStatus: \(status). Using default.")
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        let micCallback = self.onAudioSamples

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            micCallback?(samples, .me)
        }

        engine.prepare()
        try engine.start()
        self.micEngine = engine

        print("[AudioCapture] Microphone capture started (device: \(micDeviceID.map(String.init) ?? "default")). Format: \(inputFormat)")
    }

    /// Remove the tap and stop the mic engine.
    private func tearDownMicCapture() {
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
        print("[AudioCapture] Microphone capture stopped.")
    }

    // MARK: - Core Audio Helpers

    /// Read the system default output device ID.
    private func readDefaultOutputDevice() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else {
            throw AudioCaptureError.propertyReadFailed(status)
        }
        return deviceID
    }

    /// Read the UID string for an audio device.
    private func readDeviceUID(deviceID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &uid
        )
        guard status == noErr else {
            throw AudioCaptureError.propertyReadFailed(status)
        }
        return uid as String
    }

    /// Read the UID string for a process tap.
    private func readTapUID(tapID: AudioObjectID) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            tapID, &address, 0, nil, &size, &uid
        )
        guard status == noErr else {
            throw AudioCaptureError.propertyReadFailed(status)
        }
        return uid as String
    }

    /// Read the audio stream format from a process tap via `kAudioTapPropertyFormat`.
    /// The format must be read from the tap, not the output device.
    private func readTapFormat(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioObjectGetPropertyData(
            tapID, &address, 0, nil, &size, &format
        )
        guard status == noErr else {
            throw AudioCaptureError.propertyReadFailed(status)
        }
        return format
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case ioProcFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case propertyReadFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed(let s): "Failed to create audio tap (OSStatus: \(s))"
        case .aggregateDeviceFailed(let s): "Failed to create aggregate device (OSStatus: \(s))"
        case .ioProcFailed(let s): "Failed to create IO proc (OSStatus: \(s))"
        case .deviceStartFailed(let s): "Failed to start audio device (OSStatus: \(s))"
        case .propertyReadFailed(let s): "Failed to read audio property (OSStatus: \(s))"
        }
    }
}
