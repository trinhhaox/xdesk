import AppKit
import CoreGraphics
import Foundation
import XdeskWire

/// Tiêm phím Media / Âm lượng hệ thống macOS (`NX_KEYTYPE_*`) qua sự kiện `NSSystemDefined` subtype 8.
enum MediaKeyInjector {
    static func nxKeyType(for kind: MediaKeyKind) -> Int32 {
        switch kind {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }

    static func send(_ kind: MediaKeyKind) {
        let keyCode = Int(nxKeyType(for: kind))
        for down in [true, false] {
            let flagsValue: UInt = down ? 0x0A00 : 0x0B00
            let data1 = (keyCode << 16) | Int(flagsValue)
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flagsValue),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
