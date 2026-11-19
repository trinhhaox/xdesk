# Nhật ký thay đổi Xdesk

Định dạng theo từng giai đoạn (phase) của kế hoạch `plans/261118-2215-xdesk-clean-room/`.

## 0.1.0-beta (2026-11-19)

Bản beta công khai đầu tiên: DMG Mac (notarize, cập nhật qua Sparkle) và APK Android ký bằng khoá riêng.
Bản phát hành đặt tại <https://github.com/trinhhaox/xdesk-releases/releases>.

### Phase 10: đóng gói và phát hành
- Sparkle 2.10.1 trong app Mac: menu "Kiểm tra cập nhật…", kiểm tra mỗi 24 giờ, `SUVerifyUpdateBeforeExtraction`, khoá EdDSA trong Keychain.
- `tools/release-mac.sh` (archive, ký Developer ID đám mây, notarize, staple, DMG, appcast), `tools/make-dmg.sh`, `tools/release-android.sh`, `tools/verify-appcast.sh`, `tools/publish-appcast.sh`.
- Ký APK bằng keystore ngoài repo; mật khẩu trong Keychain.
- Thêm `PrivacyInfo.xcprivacy` cho app Mac và iOS, khai báo `ITSAppUsesNonExemptEncryption`.
- Sửa bộ sinh test vector: thêm các mục `agent.approve` còn thiếu.

### Phase 09: âm thanh, clipboard, USB, Tailscale
- Clipboard dùng chung giữa các thiết bị; tuỳ chọn kết nối qua Tailscale (`5b04b42`).
- Truyền âm thanh hệ thống sang iPhone/iPad; đường hầm USB cho thiết bị iOS (`0b00cd4`).

### Phase 08: máy chủ MCP cho agent AI
- Máy chủ MCP cục bộ (`5c38afb`); công cụ điều khiển một màn hình agent riêng dưới quyền người dùng (`e9585f6`).
- Android hiển thị hộp xác nhận của agent, dùng chung vector `agent.approve` (`771a589`).

### Phase 07: Android
- Ứng dụng nhận trên Android: giao thức Kotlin, mã hoá Noise, truyền tải (`082ee34`).

### Phase 06: ghép đôi và mã hoá đầu cuối
- Thư viện Noise cho ghép đôi và mã hoá phiên (`091383a`); mọi phiên đều mã hoá và bắt buộc ghép đôi (`b75661b`); giao diện ghép đôi, quản lý thiết bị đã ghép (`e976d85`).

### Phase 05: kênh điều khiển ngược
- Điều khiển Mac từ điện thoại và từ viewer Mac (`c55107f`).

### Phase 04: iOS
- App nhận iPhone/iPad dùng chung logic viewer (`2a0a0a5`); chế độ gương, màn hình ảo Retina, tự khởi động (`e1f4127`).

### Phase 03: host Mac phát tới viewer Mac
- Phát màn hình ảo từ host sang viewer (`e47d705`); truyền tải LAN và pipeline H.264 (`1a892a9`).

### Phase 02: giao thức Wire
- Giao thức Xdesk Wire v1 và bộ mã hoá Swift (`d22d78a`).

### Phase 01: nền tảng monorepo và thương hiệu
- Khung monorepo cho Mac, iOS, Android (`d854c41`).
