# Phase 07 — Receiver Android (APK)

## Context
- Phụ thuộc: 06 (spec crypto hoàn chỉnh). Có thể song song với 08 (thư mục tách biệt `android/**`).
- Thiết bị test: JP1 `adb connect 100.76.122.48:5555`, chiếu `scrcpy -s 100.76.122.48:5555`.

## Overview
- Ưu tiên: P2 · pending · 4d
- Kotlin, MediaCodec giải mã HW → `SurfaceView`, Noise cài lại bằng Kotlin, chạy chung test vectors `protocol/test-vectors/`.

## Key insights
- MediaCodec độ trễ thấp: `KEY_LOW_LATENCY=1` (API 30+, kiểm `FEATURE_LowLatency`), `KEY_PRIORITY=0`, `KEY_OPERATING_RATE` cao; chế độ async; `releaseOutputBuffer(index, true)` ngay; chọn decoder `isHardwareAccelerated` (API 29+), tránh `OMX.google.*`.
- Quirk phổ biến: decoder giữ N khung trước khi xuất (MediaTek/Unisoc) → phát hiện bằng đo "khung vào → khung ra"; giảm thiểu: H.264 profile Baseline/Constrained High không B-frame (host đã tắt reordering), gửi SPS có VUI `max_dec_frame_buffering=0` nếu VT không tự đặt thì host chèn lại SPS (bitstream rewrite nhỏ, cô lập 1 file), cuối cùng là bảng quirk theo tên codec.
- `SurfaceView` (không TextureView) để đi đường compositor ngắn nhất.
- Bonjour: `NsdManager` + `WifiManager.MulticastLock`; thêm nhập IP tay.
- Mạng: `DatagramChannel` trên thread riêng, ưu tiên `Process.THREAD_PRIORITY_URGENT_DISPLAY` cho luồng nhận/decode.
- Gõ chữ: `InputConnection` lấy chuỗi commit (Gboard/Laban Key Telex) → `input.text`.

## Requirements
- minSdk 31 (đề xuất), targetSdk mới nhất; APK sideload ký release keystore riêng.
- p50 glass-to-glass < 60 ms trên JP1 (chấp nhận cao hơn Apple ~10 ms); không rò khi xoay/nền.

## Architecture
- Module: `:wire` (codec, packetizer — JVM thuần), `:crypto` (Noise, DatagramCipher — JVM thuần), `:transport` (control TCP, UDP, NSD), `:media` (VideoDecoder, CodecSelector, QuirkTable), `:app` (Compose UI: danh sách host, quét QR bằng CameraX + ML Kit barcode hoặc ZXing, màn stream, input).
- Data flow giống Apple: NSD → TCP Noise → display.config → UDP → Reassembler → MediaCodec → Surface; touch → GestureInterpreter → InputEvent.

## Related code files (tạo, chỉ trong `android/**`)
- `wire/`: `ControlFrameCodec.kt`, `MediaHeader.kt`, `InputEvent.kt`, `Packetizer.kt`, `Reassembler.kt`, `NackTracker.kt`.
- `crypto/`: `NoiseHandshake.kt`, `CipherState.kt`, `DatagramCipher.kt`, `ReplayWindow.kt`, `ShortAuthString.kt`, `IdentityStore.kt`.
- `transport/`: `NsdBrowser.kt`, `ControlConnection.kt`, `UdpMediaChannel.kt`, `ClockSync.kt`.
- `media/`: `VideoDecoder.kt`, `CodecSelector.kt`, `DecoderQuirks.kt`.
- `app/`: `MainActivity.kt`, `HostListScreen.kt`, `PairingScreen.kt`, `StreamScreen.kt`, `StreamSurface.kt`, `TouchInput.kt`, `TextComposer.kt`.

## Implementation steps
1. `:wire` + `:crypto` với test JVM chạy chung vectors (bắt buộc xanh trước khi chạm UI).
2. Transport + NSD; kết nối host đã ghép (QR).
3. VideoDecoder + đo trễ khung vào/ra, log tên codec.
4. StreamScreen toàn màn hình (immersive), xoay.
5. Touch + bàn phím + text.
6. Build release APK, cài JP1, đo latency probe.

## Todo
- [ ] wire + crypto + vectors
- [ ] transport + NSD
- [ ] decoder + quirks
- [ ] UI stream + pairing QR
- [ ] input
- [ ] APK release + đo trên JP1

## Success criteria
- `./gradlew :wire:test :crypto:test` xanh với cùng vectors Swift.
- JP1: quét QR ghép đôi, xem màn hình ảo Mac, chạm click/cuộn được, gõ tiếng Việt đúng.
- Log decoder trên JP1: trễ khung vào→ra ≤ 1 khung; latency p50 < 60 ms (ghi số).

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Phân mảnh codec (giữ khung, không hỗ trợ low-latency) | Cao×Cao | bảng quirk, profile bảo thủ, test JP1 sớm ở bước 3, thêm máy Android thứ 2 nếu có |
| JP1 Android < 12 → thiếu XDH | TB×TB | kiểm `adb shell getprop ro.build.version.sdk` ngay bước 1; fallback lib crypto |
| Multicast bị router chặn | TB×TB | nhập IP tay, QR chứa địa chỉ |

## Security
- Khoá tĩnh lưu bằng Android Keystore wrap; `android:allowBackup=false`; không log payload.
- Quyền camera chỉ xin khi mở màn quét QR.
