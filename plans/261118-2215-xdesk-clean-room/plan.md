---
title: "Xdesk — màn hình phụ + điều khiển Mac + máy chủ MCP cho agent (clean-room)"
description: "Bộ ứng dụng Mac host/viewer, iOS, Android stream màn hình ảo độ trễ thấp, điều khiển ngược, mã hoá đầu-cuối và MCP server cho agent AI."
status: pending
priority: P1
effort: 36d
branch: main
tags: [macos, ios, android, streaming, videotoolbox, mcp, clean-room]
created: 2026-11-18
---

# Xdesk — kế hoạch tổng

## QUY TẮC CLEAN-ROOM (BẮT BUỘC, áp dụng mọi phase)
- KHÔNG đọc mã nguồn `/Users/trinhhao/Antigravity/meowdisplay` (GPLv3) hay bất kỳ binary Yosei nào. Không mở, không grep, không đưa vào context agent.
- KHÔNG chép tên, chuỗi, asset, định dạng giao thức, tên tool MCP từ chúng. Giao thức "Xdesk Wire" và UI do mình tự thiết kế.
- Chỉ dùng kiến thức mức kiến trúc (API công khai/riêng của Apple, chuẩn mở: Noise, MCP, H.264).
- Thương hiệu, icon, màu, bố cục khác biệt (bài học Xdrive bị 4.3). Ghi tại `docs/clean-room-policy.md` (phase 01); reviewer kiểm mỗi PR.

## Quyết định kiến trúc chính
- Monorepo: `apple/` (SPM `XdeskKit` + XcodeGen cho app), `android/` (Gradle Kotlin), `protocol/` (spec + test vectors dùng chung), `tools/`, `docs/`.
- MỘT app Mac "Xdesk" có 2 vai trò Host + Viewer (chung code giải mã/transport, 1 lần ký, 1 feed Sparkle).
- Video H.264 (mặc định, tương thích Android rộng) / HEVC tuỳ chọn; UDP + NACK, dự phòng TCP; điều khiển qua TCP + JSON; luồng nóng (video, input) dùng struct nhị phân cố định.
- Mã hoá: Noise (XX khi ghép đôi, IK khi kết nối lại) X25519 + ChaCha20-Poly1305 + SHA-256; ghép đôi QR (token 32B) hoặc so mã 6 số (SAS có commitment).
- MCP: Streamable HTTP rev 2025-11-25, bind 127.0.0.1, bearer token Keychain, kiểm Host/Origin.

## Phase (thứ tự = đường ngắn nhất tới demo)
| # | Phase | Effort | Phụ thuộc | Trạng thái |
|---|-------|--------|-----------|-----------|
| 01 | [Nền móng monorepo, thương hiệu, clean-room](phase-01-monorepo-foundation-and-branding.md) | 1d | — | pending |
| 02 | [Đặc tả giao thức Xdesk Wire v1 + XdeskWire](phase-02-wire-protocol-spec.md) | 2d | 01 | in review |
| 03 | [Mac host: màn hình ảo → encode → stream tới Mac viewer (LAN)](phase-03-mac-host-stream-to-mac-viewer.md) | 5d | 02 | pending |
| 04 | [Receiver iOS/iPadOS](phase-04-ios-receiver.md) | 3d | 03 | pending |
| 05 | [Kênh input ngược (pointer, touch, phím, cuộn)](phase-05-input-back-channel.md) | 3d | 03 (04 cho touch) | pending |
| 06 | [Ghép đôi + mã hoá đầu-cuối](phase-06-pairing-and-e2e-encryption.md) | 5d | 05 | pending |
| 07 | [Receiver Android](phase-07-android-receiver.md) | 4d | 06 | pending |
| 08 | [MCP server cho agent](phase-08-mcp-agent-server.md) | 5d | 05, 06 | pending |
| 09 | [Âm thanh, clipboard, USB, Tailscale](phase-09-audio-clipboard-usb-tailscale.md) | 5d | 06 | pending |
| 10 | [Đóng gói, ký, notarize, Sparkle, phát hành](phase-10-packaging-signing-release.md) | 3d | 03–09 | pending |

Thay đổi so với đề xuất ban đầu: đưa **mã hoá (06) lên trước Android (07)** để Android chỉ cài đặt transport một lần (không phải làm lại khi thêm crypto). Spec 02 đã chừa chỗ crypto từ đầu nên 03–05 chạy chế độ `dev-plaintext` (chỉ build Debug, chỉ LAN) mà không phải sửa khung.

## Chạy song song (sở hữu file tách biệt)
- 07 (`android/**`) // 08 (`apple/mac-app/Sources/Agent/**`, `apple/Packages/XdeskKit/Sources/XdeskAgent/**`) sau khi 06 xong.
- 09 tách 4 nhánh con theo thư mục: `Audio/`, `Clipboard/`, `UsbTunnel/`, `Discovery/ManualHost*`.
- File chung (`protocol/spec/*.md`, `XdeskWire/MessageTypes.swift`, `android/.../wire/MessageType.kt`) chỉ lead sửa; phase con xin thêm message type qua lead.

## Ma trận kiểm thử (tóm tắt)
- Unit: codec wire (Swift + Kotlin chạy CHUNG test vectors `protocol/test-vectors/`), Noise vectors, packetizer/reassembler mô phỏng mất gói, NACK, ABR, ánh xạ toạ độ input, policy engine MCP, kiểm Host/Origin/token.
- Integration: host↔viewer loopback trong 1 Mac; Network Link Conditioner (3% loss, 30 ms) ; MCP qua `curl` + MCP Inspector.
- E2E thiết bị thật: Mac→Mac, iPhone, iPad, JP1 (`adb connect 100.76.122.48:5555`), Claude Code điều khiển agent display.

## Rủi ro lớn (chi tiết trong từng phase)
1. CGVirtualDisplay (API riêng) đổi/vỡ qua macOS 26/27+ → lớp `VirtualDisplayProvider` + fallback mirror/cửa sổ SCK, smoke test mỗi bản beta.
2. Entitlement `com.apple.developer.hid.virtual.device` cần Apple duyệt → CGEvent trước, CoreHID là tuỳ chọn sau.
3. Độ trễ < 50 ms glass-to-glass LAN → cấu hình VT low-latency, không B-frame, đo bằng công cụ riêng (phase 03).
4. Phân mảnh codec Android (decoder giữ khung) → KEY_LOW_LATENCY, ưu tiên HW decoder, danh sách quirk, test JP1 sớm.
5. Bảo mật MCP (DNS rebinding, token lộ, agent vượt quyền) → phase 08.

## Rollback chung
- Mỗi phase merge kèm tag `phase-XX-done`; revert = `git revert` khoảng merge của phase đó (phase sau không sửa file lõi phase trước ngoài qua API công khai).
- Giao thức có `major.minor`; major lệch → từ chối kèm thông báo "Cần cập nhật Xdesk"; minor chỉ thêm, không đổi nghĩa.
- Phát hành: Sparkle không hạ cấp → sửa lỗi = phát bản mới; giữ DMG bản trước trên GitHub Releases.

## Quyết định đã chốt (18/11/2026)
- Bundle id: `vn.xox.xdesk` (Mac), `vn.xox.xdesk.ios` (iOS), applicationId Android `vn.xox.xdesk`.
- Sparkle appcast + trang tải: `https://xdesk.xox.vn` (repo GitHub private → asset Releases không tải công khai được).
- Chưa có Mac thứ hai: phase 03 test host↔viewer loopback trên cùng một Mac.
- iOS: TestFlight nội bộ trước, giữ khả năng lên App Store → app iOS KHÔNG dùng API riêng.
- Android: minSdk 31; JP1 chạy Android 13 (SDK 33), có sẵn XDH + ChaCha20-Poly1305 → không cần Tink/BouncyCastle.
- MCP mặc định cấm: System Settings, Keychain Access, Passwords, Terminal/iTerm, trình quản lý mật khẩu (1Password, Bitwarden).

## Câu hỏi mở
Xem cuối từng phase.
