import CoreAudio
import Foundation

/// Manages audio device enumeration and selection for both input (mic) and output (TTS routing).
final class AudioDeviceManager {

    // MARK: - Device info

    struct AudioDevice: Identifiable, Hashable {
        let id: AudioDeviceID
        let uid: String
        let name: String
        let transportType: UInt32
        let isInput: Bool
        let isOutput: Bool
        let sampleRate: Float64
        let channelCount: UInt32

        var isVirtual: Bool {
            transportType == kAudioDeviceTransportTypeVirtual
        }

        var isBlackHole: Bool {
            name.lowercased().contains("blackhole")
        }

        var isBuiltIn: Bool {
            transportType == kAudioDeviceTransportTypeBuiltIn
        }

        var displayName: String {
            if isBlackHole { return "\(name) (虚拟设备)" }
            if isBuiltIn { return "\(name) (内建)" }
            return name
        }
    }

    // MARK: - Enumerate devices

    static func enumerateInputDevices() -> [AudioDevice] {
        allDevices().filter { $0.isInput }
    }

    static func enumerateOutputDevices() -> [AudioDevice] {
        allDevices().filter { $0.isOutput }
    }

    static func findBlackHoleDevice() -> AudioDevice? {
        enumerateOutputDevices().first { $0.isBlackHole || $0.name.lowercased().contains("blackhole") }
    }

    static func findDefaultInputDevice() -> AudioDevice? {
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return nil }
        return deviceInfo(id: deviceID)
    }

    // MARK: - Instance wrappers (for SwiftUI bindings)

    func enumerateInputDevices() -> [AudioDevice] { Self.enumerateInputDevices() }
    func enumerateOutputDevices() -> [AudioDevice] { Self.enumerateOutputDevices() }
    func findBlackHoleDevice() -> AudioDevice? { Self.findBlackHoleDevice() }

    static func findDefaultOutputDevice() -> AudioDevice? {
        var deviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr else { return nil }
        return deviceInfo(id: deviceID)
    }

    // MARK: - Private helpers

    private static func allDevices() -> [AudioDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        )

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        )

        return ids.compactMap { deviceInfo(id: $0) }
    }

    private static func deviceInfo(id: AudioDeviceID) -> AudioDevice? {
        var uid: CFString?
        var uidSize = UInt32(MemoryLayout<CFString?>.size)
        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let uidStatus = AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid)
        guard uidStatus == noErr, let uid = uid else { return nil }

        var name: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)

        var transportType: UInt32 = 0
        var transportSize = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transportType)

        var sampleRate: Float64 = 0
        var srSize = UInt32(MemoryLayout<Float64>.size)
        var srAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(id, &srAddress, 0, nil, &srSize, &sampleRate)

        var inputChannelCount: UInt32 = 0
        var inputChSize = UInt32(MemoryLayout<UInt32>.size)
        var inputChAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(id, &inputChAddress, 0, nil, &inputChSize)
        let hasInput = inputChSize > MemoryLayout<UInt32>.size

        var outputChannelCount: UInt32 = 0
        var outputChSize = UInt32(MemoryLayout<UInt32>.size)
        var outputChAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyDataSize(id, &outputChAddress, 0, nil, &outputChSize)
        let hasOutput = outputChSize > MemoryLayout<UInt32>.size

        return AudioDevice(
            id: id,
            uid: String(uid),
            name: (name as String?) ?? "Unknown",
            transportType: transportType,
            isInput: hasInput,
            isOutput: hasOutput,
            sampleRate: sampleRate > 0 ? sampleRate : 44100,
            channelCount: hasInput ? inputChannelCount : outputChannelCount
        )
    }
}
