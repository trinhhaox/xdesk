import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os
import XdeskInput

enum TextInjectionOutcome: Equatable {
    case typed
    /// Một app đang bật Secure Event Input (ô mật khẩu…): ký tự có thể không vào được ô đích.
    case typedWhileSecureInput
}

/// Gõ chuỗi Unicode đã commit (IME/Telex phía điện thoại) bằng `CGEventKeyboardSetUnicodeString`, ≤ 20 đơn vị UTF-16 mỗi cụm.
struct TextInjector: Sendable {
    static let chunkLimit = 20
    private static let log = Logger(subsystem: "vn.xox.xdesk", category: "text-injector")

    static func chunks(_ text: String) -> [[UniChar]] {
        TextChunker.split(text, limit: chunkLimit) { $0.utf16.count }
            .map { Array($0.utf16) }
            .filter { chunk in
                let fits = chunk.count <= chunkLimit
                if !fits { log.error("bỏ ký tự dài \(chunk.count) đơn vị UTF-16") }
                return fits
            }
    }

    static var isSecureInputActive: Bool { IsSecureEventInputEnabled() }

    func type(_ text: String, flags: CGEventFlags = []) -> TextInjectionOutcome {
        let source = CGEventSource(stateID: .combinedSessionState)
        for var chunk in Self.chunks(text) {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                    Self.log.error("không tạo được CGEvent bàn phím")
                    continue
                }
                event.flags = flags
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                event.post(tap: .cghidEventTap)
            }
        }
        return Self.isSecureInputActive ? .typedWhileSecureInput : .typed
    }
}
