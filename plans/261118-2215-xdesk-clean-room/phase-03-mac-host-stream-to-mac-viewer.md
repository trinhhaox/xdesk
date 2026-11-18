# Phase 03 — Mac host: màn hình ảo → capture → encode → stream tới Mac viewer (LAN)

## Context
- Phụ thuộc: 02 (XdeskWire). Spec: `protocol/spec/media-packets.md`.
- API: CGVirtualDisplay (riêng, chấp nhận vì phát hành ngoài App Store), ScreenCaptureKit `SCStream`, VideoToolbox, Network.framework `NWListener`/`NWConnection`, Bonjour.

## Overview
- Ưu tiên: P1 · pending · 5d
- Demo đầu tiên: Mac A tạo màn hình ảo "mở rộng", Mac viewer (cùng app, vai trò Viewer — có thể chạy trên CHÍNH Mac A qua loopback nếu chỉ có 1 máy) hiển thị mượt.

## Key insights
- CGVirtualDisplay: khai báo header Obj-C riêng (`CGVirtualDisplayDescriptor`, `Mode`, `Settings`) trong bridging header; kiểm runtime `NSClassFromString`; màn hình sống khi object còn được giữ → `VirtualDisplayProvider` sở hữu vòng đời. Hỗ trợ HiDPI bằng mode 2× (`hiDPI=1`).
- Fallback nếu class biến mất/đổi chữ ký: chế độ Mirror (capture màn hình chính) hoặc Single Window (`SCContentFilter(desktopIndependentWindow:)`) — vẫn dùng được, không crash.
- VT low-latency: `kVTVideoEncoderSpecification_EnableLowLatencyRateControl` (H.264), `RealTime=true`, `AllowFrameReordering=false`, `MaxFrameDelayCount=0`, `ExpectedFrameRate=60`, keyframe khi được yêu cầu (`kVTEncodeFrameOptionKey_ForceKeyFrame`), `MaxKeyFrameInterval` dài (≈ 5 s) vì có NACK.
- SCStream: `queueDepth` 3, `minimumFrameInterval` 1/60, pixel format `420v` (khớp encoder, tránh chuyển đổi), `showsCursor=true` (YAGNI kênh con trỏ riêng). SCK chỉ phát khung khi có thay đổi → màn tĩnh tốn ~0 băng thông.
- Giải mã Apple: đưa `CMSampleBuffer` vào `AVSampleBufferDisplayLayer` với attachment `DisplayImmediately` — đơn giản nhất, HW decode; dùng chung cho Mac viewer và iOS (phase 04).
- ABR đơn giản AIMD: loss > 2% hoặc RTT tăng > 30% → bitrate ×0.8; ổn định 2 s → +5%; sàn 2 Mb/s, trần 40 Mb/s LAN.

## Requirements
- Chức năng: Host quảng bá `_xdesk._tcp` (TXT: `v=1`, `id=<fingerprint ngắn>`, `n=<tên Mac>`); Viewer liệt kê, chọn, kết nối; chế độ Extend/Mirror/Window; độ phân giải theo viewer yêu cầu.
- Phi chức năng: glass-to-glass p50 < 50 ms, p95 < 80 ms ở 1920×1200@60 Wi-Fi 5 GHz/Ethernet; CPU host < 15% (M-series); không rò bộ nhớ khi kết nối/ngắt 100 lần.

## Architecture
```
[VirtualDisplayProvider] → displayID → [CaptureService(SCStream)] → CVPixelBuffer
 → [VideoEncoder(VTCompressionSession)] → AVCC NAL → [Packetizer] → [MediaSender(NWConnection UDP)]
                         ↑ keyframe.request / bitrate.set ← [ControlSession(TCP JSON)] ← net.report
Viewer: [MediaReceiver UDP] → [Reassembler + NackTracker] → [FrameAssembler → CMSampleBuffer] → [AVSampleBufferDisplayLayer]
```
- Đo độ trễ: `tools/latency-probe/` — host vẽ đồng hồ ms + mã khung lên màn hình ảo (app phụ trợ); viewer chồng đồng hồ của mình (đã đồng bộ qua ping/pong 4 mốc). Đối chiếu thêm bằng quay slow-mo 240 fps 2 màn hình.

## Related code files (tạo)
- `XdeskTransport/`: `BonjourAdvertiser.swift`, `BonjourBrowser.swift`, `ControlListener.swift`, `ControlConnection.swift`, `UdpMediaChannel.swift`, `ClockSync.swift`.
- `XdeskMedia/`: `VideoEncoder.swift`, `EncoderSettings.swift`, `BitrateController.swift`, `FrameAssembler.swift`, `SampleBufferFactory.swift`, `VideoLayerRenderer.swift`.
- `mac-app/Sources/Host/`: `VirtualDisplayProvider.swift`, `CGVirtualDisplayBridge.h`, `CaptureService.swift`, `HostSession.swift`, `HostController.swift`.
- `mac-app/Sources/Viewer/`: `ViewerBrowserView.swift`, `ViewerWindow.swift`, `ViewerSession.swift`.
- `mac-app/Sources/App/`: `XdeskApp.swift`, `MenuBarContent.swift`, `PermissionsCheck.swift` (Screen Recording).
- `tools/latency-probe/`.

## Implementation steps
1. `VirtualDisplayProvider`: tạo/huỷ màn hình, liệt kê mode, kiểm `isAvailable`; unit test hành vi fallback bằng protocol giả lập.
2. `CaptureService`: SCStream lọc theo displayID, xin quyền Screen Recording, xử lý `stream(_:didStopWithError:)` (màn hình bị huỷ, người dùng thu hồi quyền).
3. `VideoEncoder` + `EncoderSettings` (H.264 High/Main, HEVC khi viewer báo hỗ trợ).
4. Control session: hello/welcome/display.config/display.ready; Bonjour.
5. UDP media + Packetizer; Viewer Reassembler + NACK + keyframe.request.
6. Viewer renderer + cửa sổ toàn màn hình tuỳ chọn.
7. `BitrateController` + `net.report` mỗi 500 ms.
8. Latency probe, đo, ghi kết quả vào `plans/reports/latency-phase-03.md`.

## Todo
- [x] VirtualDisplayProvider + fallback Mirror (03b: CGVirtualDisplay thật tạo 1920×1200 mở rộng, biến mất khi ngắt; fallback test bằng giả lập; fallback Window CHƯA làm)
- [x] CaptureService (03b: SCStream 420v/queueDepth 3/60 fps chạy thật qua loopback; xử lý thiếu quyền + didStopWithError)
- [x] VideoEncoder low-latency (03a: lib + test mã hoá→giải mã 30 khung thật)
- [ ] Control + Bonjour (Control/handshake chạy thật trong app 03b; Bonjour CHƯA kiểm: hộp thoại Local Network chờ người dùng bấm Cho phép)
- [x] UDP media + NACK (03a: lib + test loopback mất gói/NACK/keyframeNeeded)
- [x] Viewer render (03b: ảnh chụp cửa sổ viewer thấy khung host; toàn màn hình tuỳ chọn viết, chưa thử tay)
- [ ] ABR (03b: net.report 500 ms → BitrateController → bitrate.set đã nối; loopback không bao giờ nghẽn nên nhánh giảm bitrate chưa chạy thật)
- [x] Latency probe + số đo (loopback 1 Mac: p50 34–35 ms, p95 52 ms — xem plans/reports/latency-phase-03.md; chưa đo Wi-Fi/Ethernet 2 máy)

## Success criteria (thiết bị thật)
- Mac host: System Settings → Displays hiện màn hình "Xdesk" mới; kéo cửa sổ sang được.
- Viewer thấy hình ≤ 2 s sau khi bấm kết nối; 30 phút không đứng hình; ngắt Wi-Fi 5 s → tự hồi (keyframe) ≤ 1 s sau khi có mạng.
- Latency probe: p50 < 50 ms, p95 < 80 ms (ghi số thật); NLC 3% loss: không vỡ hình quá 1 khung.
- Kết nối/ngắt 100 lần (script) — Instruments Leaks sạch; màn hình ảo biến mất khi ngắt.

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| CGVirtualDisplay đổi chữ ký trên macOS 27.x | TB×Cao | bridge cô lập 1 file, kiểm `respondsToSelector`, fallback Mirror, smoke test mỗi beta |
| Độ trễ Wi-Fi vượt 50 ms (power-save, AWDL) | Cao×TB | khuyến nghị Ethernet/5 GHz, gửi đều đặn tránh ngủ radio, đo báo cáo trung thực |
| SCK thêm trễ khung (queue) | TB×TB | queueDepth nhỏ, bỏ khung cũ khi encoder bận |
| Quyền Screen Recording hỏi lại hàng tháng (macOS 15+) | Cao×Thấp | UI hướng dẫn, phát hiện mất quyền rõ ràng |

## Security
- Phase này chạy `dev-plaintext` chỉ ở build Debug; build Release từ chối kết nối không mã hoá (assert compile-time `#if DEBUG`).
- Listener chỉ nhận trên interface LAN/loopback; giới hạn 4 viewer đồng thời.

## Rollback
- Toàn bộ code nằm trong thư mục mới; revert phase không ảnh hưởng 01–02.
