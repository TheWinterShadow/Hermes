import CoreAudio
import Foundation

/// Represents an audio input device.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
}

/// Enumerates and monitors system audio input devices.
@MainActor
final class AudioDeviceManager: ObservableObject {
    @Published var inputDevices: [AudioInputDevice] = []
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

    /// Re-enumerate all input devices.
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
