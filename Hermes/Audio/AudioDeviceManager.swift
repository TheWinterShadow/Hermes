import CoreAudio
import Foundation

/// Represents an audio input device discovered on the system.
struct AudioInputDevice: Identifiable, Hashable {
    /// Core Audio device ID — used to configure AVAudioEngine's input node.
    let id: AudioDeviceID

    /// Human-readable device name (e.g., "MacBook Pro Microphone").
    let name: String

    /// Persistent unique identifier string for the device.
    let uid: String
}

/// Enumerates and monitors system audio input devices.
///
/// Provides a list of available input devices for the mic picker in the overlay UI.
/// Filters out non-input devices and Hermes's own aggregate devices (created by
/// `AudioCaptureManager` for CATap system audio capture).
@MainActor
final class AudioDeviceManager: ObservableObject {
    /// All discovered input devices, excluding Hermes aggregate devices.
    @Published var inputDevices: [AudioInputDevice] = []

    /// The user's selected input device. `nil` means "use system default".
    @Published var selectedDeviceID: AudioDeviceID?

    /// The system default input device ID, used as fallback.
    var defaultInputDeviceID: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    init() {
        refresh()
        selectedDeviceID = defaultInputDeviceID
    }

    /// Re-enumerate all input devices from Core Audio.
    ///
    /// Queries `kAudioHardwarePropertyDevices`, then filters each device to include only
    /// those with input streams (`kAudioDevicePropertyStreams` in input scope). Also
    /// excludes any device whose name starts with "Hermes-" (our aggregate devices).
    func refresh() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else {
            inputDevices = []
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else {
            inputDevices = []
            return
        }

        var result: [AudioInputDevice] = []
        for id in deviceIDs {
            // Check if device has input streams
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &inputAddress, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            // Skip aggregate devices we created
            let name = deviceName(for: id)
            if name.hasPrefix("Hermes-") { continue }

            let uid = deviceUID(for: id)
            result.append(AudioInputDevice(id: id, name: name, uid: uid))
        }

        inputDevices = result
    }

    /// Returns the human-readable name for a Core Audio device.
    ///
    /// - Parameter deviceID: The `AudioDeviceID` to query.
    /// - Returns: The device name string, or empty string on failure.
    private func deviceName(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        return name as String
    }

    /// Returns the persistent UID string for a Core Audio device.
    ///
    /// - Parameter deviceID: The `AudioDeviceID` to query.
    /// - Returns: The device UID string, or empty string on failure.
    private func deviceUID(for deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        return uid as String
    }
}
