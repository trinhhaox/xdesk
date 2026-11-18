# Phase 05 — Kênh input ngược (pointer, touch, bàn phím, cuộn)

## Context
- Phụ thuộc: 03 (Mac viewer), 04 (iOS touch). Spec input: `protocol/spec/media-packets.md` mục Input.
- API: `CGEvent` + `CGEventPost(.cghidEventTap)`, quyền Accessibility (`AXIsProcessTrustedWithOptions`).

## Overview
- Ưu tiên: P1 · pending · 3d
- Viewer gửi sự kiện; Host tiêm vào đúng màn hình ảo. CGEvent là đường chính; CoreHID virtual HID để sau (entitlement cần Apple duyệt).

## Key insights
- Toạ độ chuẩn hoá 0…1 trên khung video → Host đổi sang điểm toàn cục bằng `CGDisplayBounds(displayID)` (xử lý màn hình đặt bên trái/trên có toạ độ âm).
- Phím: gửi HID usage (vị trí phím, không phụ thuộc layout) → bảng ánh xạ HID→`CGKeyCode` mac; modifiers gửi kèm mỗi sự kiện để tránh kẹt.
- Gõ tiếng Việt từ bàn phím ảo iOS/Android (Telex do OS điện thoại xử lý) → gửi **chuỗi đã commit** qua `input.text`, Host dùng `CGEventKeyboardSetUnicodeString` theo cụm ≤ 20 ký tự. Bàn phím vật lý nối iPad → gửi HID usage để bộ gõ trên Mac (Xmac) xử lý.
- Touch → cử chỉ chuột (CGEvent không có touch thật): chạm = click, giữ 500 ms = chuột phải, kéo 1 ngón = drag, 2 ngón = scroll pixel (`CGEvent(scrollWheelEvent2Source:units:.pixel)`) có quán tính do Mac tự làm phần lớn; chế độ "trackpad" (di chuyển tương đối) tuỳ chọn. Pinch/rotate: YAGNI v1.
- Apple Pencil: dùng như chuột trái chính xác; áp lực để sau.
- Kẹt phím/nút: Host có watchdog — mất gói `up` hoặc viewer ngắt → nhả hết nút/phím đang giữ. `down/up/key` có seq + `input-ack`; gửi lại tối đa 3 lần.

## Requirements
- Chuột Mac viewer: move/click/double/drag/scroll (cả trackpad momentum), phím kể cả ⌘-Tab khi viewer ở chế độ "chụp phím hệ thống" (CGEventTap trên viewer, cần Accessibility ở viewer).
- Độ trễ input→pixel trên viewer < 60 ms p50.

## Architecture
```
Viewer: NSEvent/UITouch/UIPress → [InputMapper] → InputEvent(24B) → UDP (seq) ─┐
Host:  UDP → [InputDecoder] → [StuckInputGuard] → [CoordinateMapper(displayID)] → [EventInjector(CGEvent)]
       control JSON input.text → [TextInjector]
```

## Related code files (tạo)
- `XdeskInput/`: `HidKeyMap.swift`, `InputMapper.swift` (chung), `GestureInterpreter.swift` (touch→pointer), `InputSequencer.swift`.
- `mac-app/Sources/Host/Input/`: `EventInjector.swift`, `TextInjector.swift`, `CoordinateMapper.swift`, `StuckInputGuard.swift`, `AccessibilityPermission.swift`.
- `mac-app/Sources/Viewer/Input/`: `ViewerEventCapture.swift`, `SystemShortcutTap.swift`.
- `ios-app/Sources/Input/`: `TouchInputView.swift`, `HardwareKeyboardHandler.swift`, `TextComposerBar.swift` (thanh gõ chữ).

## Implementation steps
1. Bảng HID→CGKeyCode + test (A–Z, số, F1–F12, mũi tên, modifier trái/phải).
2. CoordinateMapper + test nhiều bố cục màn hình (âm, scale 2×).
3. EventInjector, TextInjector, StuckInputGuard (unit test bằng injector giả).
4. Viewer Mac capture; iOS touch + bàn phím cứng + thanh gõ chữ.
5. Quy trình xin quyền Accessibility có hướng dẫn rõ ràng.

## Todo
- [x] HidKeyMap + test
- [x] CoordinateMapper + test
- [x] Injector + guard (host; 05a)
- [ ] Capture Mac viewer (code + unit test xong, bật bằng tay: chưa thử chuột/phím thật qua cửa sổ viewer)
- [ ] iOS touch/keyboard/text (code + test xong, đã cài iPhone + stream; chạm/phím/gõ chữ thật chưa thử)
- [ ] Đo độ trễ input

## Success criteria
- Từ iPad: mở Finder, kéo-thả file, cuộn Safari mượt, gõ "Tiếng Việt có dấu" đúng 100% vào TextEdit.
- Từ Mac viewer: ⌘-Tab, ⌘-Space hoạt động trên Mac host khi bật chế độ chụp phím.
- Rút Wi-Fi giữa lúc kéo → host nhả nút ≤ 1 s (không kẹt drag).
- Click lệch ≤ 1 px trên màn hình ảo đặt bên trái màn hình chính (toạ độ âm).

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Entitlement HID ảo không được duyệt | Cao×Thấp | CGEvent đủ cho v1; nộp đơn song song, không chặn |
| Secure Event Input (ô mật khẩu) chặn CGEvent gõ | TB×TB | phát hiện `IsSecureEventInputEnabled`, báo người dùng |
| Unicode string bị app Electron xử lý sai | TB×TB | chia cụm nhỏ, fallback gõ từng ký tự |

## Security
- Chỉ nhận input từ phiên đã xác thực (bắt buộc ở Release sau 06); phiên chỉ xem ("view-only") bỏ mọi input.
- Giới hạn tốc độ 1000 sự kiện/s/phiên.
