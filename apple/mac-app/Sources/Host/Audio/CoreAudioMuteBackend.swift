import CoreAudio
import Foundation

/// Tắt/bật tiếng thiết bị ra qua CoreAudio (`kAudioDevicePropertyMute`): kênh chính (element 0), hoặc từng kênh 1,2 nếu thiết bị không có kênh chính.
struct CoreAudioMuteBackend: OutputMuteBackend {
    func defaultOutputUID() -> String? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var uidAddress = Self.address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    func isMuted(uid: String) -> Bool? {
        guard let device = Self.device(forUID: uid) else { return nil }
        let states = Self.elements(of: device).compactMap { element -> Bool? in
            var address = Self.muteAddress(element)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
        }
        return states.isEmpty ? nil : states.allSatisfy { $0 }
    }

    @discardableResult
    func setMuted(_ muted: Bool, uid: String) -> Bool {
        guard let device = Self.device(forUID: uid) else { return false }
        var applied = false
        for element in Self.elements(of: device) {
            var address = Self.muteAddress(element)
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr { applied = true }
        }
        return applied
    }

    /// Master nếu có, không thì kênh 1 và 2.
    private static func elements(of device: AudioObjectID) -> [UInt32] {
        var master = muteAddress(kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &master) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter { element in
            var address = muteAddress(element)
            return AudioObjectHasProperty(device, &address)
        }
    }

    private static func device(forUID uid: String) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func muteAddress(_ element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
}
