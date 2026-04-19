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

    func startCapture() throws {
        guard !isCapturing else { return }

        try setupSystemAudioTap()
        try setupMicCapture()

        isCapturing = true
        isPaused = false
    }

    func stopCapture() {
        tearDownMicCapture()
        tearDownSystemAudioTap()
        isCapturing = false
        isPaused = false
        gSystemAudioPaused = false
    }

    func pauseCapture() {
        guard isCapturing, !isPaused else { return }
        micEngine?.pause()
        gSystemAudioPaused = true
        isPaused = true
        print("[AudioCapture] Paused.")
    }

    func resumeCapture() {
        guard isCapturing, isPaused else { return }
        gSystemAudioPaused = false
        try? micEngine?.start()
        isPaused = false
        print("[AudioCapture] Resumed.")
    }

    // MARK: - System Audio (CATap)

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
    /// kAudioAggregateDevicePropertyTapList after creation.
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

    private func tearDownMicCapture() {
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil
        print("[AudioCapture] Microphone capture stopped.")
    }

    // MARK: - Core Audio Helpers

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
