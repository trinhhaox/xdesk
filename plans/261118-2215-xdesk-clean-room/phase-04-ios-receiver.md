# Phase 04 — Receiver iOS/iPadOS

## Context
- Phụ thuộc: 03 (XdeskTransport, XdeskMedia đã chạy trên Mac). Tái dùng ~90% code Viewer qua SPM.

## Overview
- Ưu tiên: P1 · pending · 3d
- App "Xdesk" iOS/iPadOS: tìm host qua Bonjour, hiển thị màn hình ảo đúng độ phân giải gốc thiết bị.

## Key insights
- iOS cần `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_xdesk._tcp`), nếu thiếu browse im lặng thất bại.
- Viewer gửi `display.config` = kích thước điểm × scale của màn hình (iPad Pro 13" ~ 2752×2064) → host tạo mode HiDPI tương ứng, chữ sắc nét.
- App phải ở foreground (iOS treo socket nền) → giữ `isIdleTimerDisabled=true` khi đang xem; khi vào nền gửi `bye` lịch sự, host giữ màn hình ảo 30 s để quay lại nhanh.
- ProMotion 120 Hz: để sau (YAGNI); mặc định 60.

## Requirements
- iOS/iPadOS 18+; iPhone + iPad; xoay màn hình → đổi `display.config` (host đổi mode, không tạo lại màn hình nếu có thể).
- Độ trễ như phase 03; pin: ≤ 15%/giờ trên iPad khi stream 60 fps (ghi số đo).

## Architecture
- `ios-app/Sources/`: `XdeskIOSApp.swift`, `HostListView.swift`, `StreamView.swift` (UIViewRepresentable chứa `AVSampleBufferDisplayLayer`), `StreamViewModel.swift`, `OrientationObserver.swift`.
- Dữ liệu: Bonjour → chọn host → ControlConnection → UDP media → renderer (dùng chung XdeskMedia).

## Related code files
- Tạo: các file trên, `ios-app/Resources/Info.plist` keys, asset icon iOS theo brand-guide.
- Sửa (qua lead): `XdeskMedia/VideoLayerRenderer.swift` nếu cần tách UIKit/AppKit bằng `#if canImport`.

## Implementation steps
1. Màn danh sách host + nhập thủ công IP:port (dùng lại cho Tailscale ở 09).
2. StreamView toàn màn hình, ẩn status bar, letterbox khi tỉ lệ lệch.
3. Xử lý vòng đời scene (nền/foreground/khoá máy), reconnect.
4. Xoay màn hình → display.config mới.
5. Chạy trên iPhone + iPad thật (ký development team 4DU4BTV46U).

## Todo
- [ ] HostListView + nhập tay
- [ ] StreamView + renderer
- [ ] Vòng đời + reconnect
- [ ] Xoay màn hình
- [ ] Đo latency + pin trên iPad/iPhone

## Success criteria
- iPad thật hiển thị màn hình mở rộng của Mac, kéo cửa sổ sang iPad mượt, chữ sắc ở scale 2×.
- Khoá iPad 10 s rồi mở → hình trở lại ≤ 2 s.
- Latency probe iPad p50 < 50 ms (Wi-Fi 5 GHz).

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Người dùng từ chối Local Network → không thấy host | TB×Cao | màn hướng dẫn mở Settings; nhập IP tay |
| HEVC 4:2:0 10-bit không hỗ trợ trên iPhone cũ | Thấp×TB | thương lượng codec qua caps, mặc định H.264 |

## Security
- Vẫn dev-plaintext (Debug). Không lưu gì nhạy cảm trên iOS ở phase này.

## Next steps
- 05 thêm cảm ứng/bàn phím từ iPad.
