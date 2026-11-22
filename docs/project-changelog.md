# Nhật ký thay đổi Xdesk

Định dạng theo từng giai đoạn (phase) của kế hoạch `plans/261118-2215-xdesk-clean-room/`.

## Chưa phát hành

## 0.2.1-beta (2026-11-23)

Chi tiết: `docs/release-notes/0.2.1-beta.md`.
- Bàn phím Mac đầy đủ trên điện thoại (HID thật, phím bổ trợ dính/khoá/giữ, lặp phím, lớp `fn`); giao diện Bàn phím / Slide & Số mới cho dọc và ngang, thanh trên một hàng; bàn phím số gửi HID keypad.
- Chế độ điều khiển dùng màn hình gốc của Mac (không màn hình ảo, không co cửa sổ, xoay điện thoại không đổi `display.config`).
- Chỉnh cửa sổ Mac từ điện thoại: capability bit 14 `windowControl`, message `window.pick` / `window.selected` / `window.adjust` (move, resize, preset fill/left/right/center/restore), host dùng AX, cửa sổ chỉnh tay không bị WindowFitter co/khôi phục.
- Android: giải mã audio trên luồng riêng (`AsyncAudioSink`) — trước đó decoder AAC chặn luồng UDP, host cắt phiên sau 10 s qua Tailscale; bộ đệm jitter tự tăng tới 200 ms.
- ABR: trần 5 Mb/s khi RTT > 80 ms (relay).
- Khoá Mac bằng `SACLockScreenImmediate`; sửa nhận diện màn hình khoá (`kCGSSessionOnConsoleKey`); thử lại video lỗi khi Mac còn khoá thì giữ phiên.
- Nút "Đặt lại khoá" có đếm ngược cửa sổ đăng ký 5 phút.
- `xcodebuild test` dùng Xdesk.app làm test host giờ chạy app rỗng (không mở Keychain, không chia sẻ cổng 47800).

- Mac ngủ/khoá màn hình không còn làm rớt phiên: lệnh khoá từ xa tắt màn hình khiến SCStream dừng và host gửi `bye` (điện thoại rớt rồi kết nối lại liên tục, kết nối lại thì tạo màn hình ảo hỏng). Giờ host giữ phiên ở trạng thái "chưa có hình" (kênh điều khiển, keepalive UDP, input, khoá/mở khoá, clipboard vẫn chạy), gửi message mới `host.state {videoAvailable, locked}` (host→viewer, không cần cap), tự bật lại video bằng keyframe khi màn hình thức/mở khoá (`screensDidWake`, `sessionDidBecomeActive`, `com.apple.screenIsUnlocked` + poll dự phòng 3 s). iOS/Android hiện lớp phủ "Mac đang khoá" kèm nút "Mở khoá Mac" và "Ngắt kết nối". Lỗi capture thật (không do ngủ/khoá) vẫn kết thúc phiên như cũ.
- Mở khoá Mac bằng Face ID/vân tay giờ gắn với chữ ký mật mã của điện thoại (capability bit 13 `unlockAttestation`): điện thoại giữ khoá P-256 (iOS Secure Enclave `userPresence`, Android AndroidKeyStore + BiometricPrompt CryptoObject), Mac phát nonce dùng một lần 30 s và chỉ gõ mật khẩu khi chữ ký khớp khoá đã đăng ký (TOFU, lưu trong bản ghi thiết bị có HMAC). Viewer cũ hoặc thiết bị chưa đăng ký khoá chỉ đánh thức màn hình, không gõ mật khẩu. Tắt quyền "Mở khoá Mac" hoặc bấm "Đặt lại khoá" ở Cài đặt › Thiết bị để đăng ký lại khoá. Message mới `unlock.key`, `system.unlock.challenge`, trường `sig` của `system.unlock`; spec `control-messages.md`, vector `control-frames.json`. Chữ ký gắn khoá tĩnh Noise của host và viewer, viewer chỉ ký sau khi người dùng bấm mở khoá, khoá chỉ đăng ký trong 5 phút sau khi bật quyền/"Đặt lại khoá" trên Mac (thiết bị đã bật quyền từ trước phải đặt lại khoá một lần); Mac và điện thoại hiện dấu vân tay khoá để đối chiếu. Thêm `system.lock.result` (báo "Mac chỉ tắt màn hình" khi không khoá được), giới hạn tần suất mở khoá theo thiết bị, và chỉ coi Mac đã khoá khi phiên đang ở console. **Hạ cấp xuống bản trước không được hỗ trợ**: file danh sách thiết bị có khoá ghi `schemaVersion` 2 nên bản cũ từ chối đọc (giữ nguyên file). Cần thử trên máy thật (Secure Enclave/AndroidKeyStore không chạy được trên simulator).
- Mac tự chạy `adb reverse tcp:47800 tcp:<cổng host>` khi có điện thoại Android cắm cáp (đã bật USB debugging) trong lúc đang phát: cứ 4 giây xem `adb devices`, rút cáp rồi cắm lại thì làm lại; không có `adb` thì bỏ qua. Media Android qua cáp đi bằng MediaOverTcp. Mã: `apple/mac-app/Sources/UsbTunnel/AdbReverseWatcher.swift`; mô tả: `protocol/spec/framing.md`, `docs/audio-and-usb.md`.
- `make test-ios` giờ chạy test thật trên iOS Simulator (`xcodebuild test`, chọn máy bằng `IOS_SIM_ID=<udid>`, mặc định iPhone đầu tiên còn dùng được) thay vì chỉ `build-for-testing`.
- Quyền truyền tệp riêng cho từng thiết bị: gửi/nhận tệp (`file.*`) tách khỏi quyền điều khiển (`input`) thành quyền riêng, bật/tắt theo từng thiết bị đã ghép. Đang được hoàn thiện song song; không đổi định dạng wire.
- Spec và test vector giao thức khớp mã 0.2.0-beta: `control-messages.md` có đủ message `display.reconfigure`, `display.list`, `video.pause/resume`, `file.*`, `system.lock/unlock(.result)`, `media.key`, `agent.help`; `xdesk-wire-v1-overview.md` có capability bit 7–12; `control-frames.json` thêm vector cho mọi type này (Swift và Kotlin cùng chạy), thêm test bảo đảm mọi type đều có vector.
- Tài liệu: `docs/mcp-setup.md` (15 tool, công tắc MCP nằm ở Cài đặt › Agent AI, tool `xdesk_request_user_help`).

## 0.2.0-beta (2026-11-22)

Chi tiết: `docs/release-notes/0.2.0-beta.md`.
- 5 chế độ làm việc thống nhất; `video.pause`/`video.resume` tạm dừng capture/encode khi ở chế độ chỉ điều khiển; `display.reconfigure` đổi chế độ/kiểu chiếu không ngắt kết nối.
- Tự kết nối lại (1 s → 2 s → 4 s, chuyển LAN sang Tailscale), trợ lý Tailscale, media Android qua USB bằng MediaOverTcp.
- Đồng bộ clipboard 2 chiều trên Android (văn bản và PNG ≤ 10 MiB, SHA-256); truyền tệp streaming 2 chiều `file.start/chunk/done/cancel` (≤ 2 GiB, mảnh 64 KiB, SHA-256, Mac lưu vào `~/Downloads/Xdesk/`).
- Mở khoá Mac từ xa (`system.unlock`, mật khẩu trong Keychain, quyền kép, sinh trắc học trên điện thoại, giới hạn 3 lần/60 s); chọn màn hình Mac (`display.list`) và vị trí màn hình phụ; FPS 30/60/120, phím media (`media.key`), cử chỉ trackpad; chọn HEVC/H.264 trên iOS và Android.
- Capability bit 7–12 (`hotReconfigure`, `videoPause`, `fileTransfer`, `remoteUnlock`, `mediaKeys`, `multiDisplay`).

## 0.1.9-beta (2026-11-22)

Chi tiết: `docs/release-notes/0.1.9-beta.md`.
- Nhập địa chỉ thủ công tự thêm cổng 47800; Android tự nhận máy Mac đã ghép khi đổi IP (LAN sang Tailscale).
- Sửa nút "Nối cáp USB" (Android) truyền nhầm địa chỉ cũ; sửa lớp phủ "Đang kết nối…" kẹt ở chế độ Trackpad; tự xin keyframe khi chuyển sang xem màn hình.

## 0.1.8-beta (2026-11-22)

Chi tiết: `docs/release-notes/0.1.8-beta.md`.
- Chế độ Bàn phím & Chuột ảo chuyên dụng toàn màn hình mở thẳng từ danh sách máy Mac, không cần luồng video; chuyển nhanh giữa trackpad và xem màn hình.
- Đồng bộ giao diện iOS/Android; ngắt kết nối và giải phóng tài nguyên khi thoát chế độ này.

## 0.1.7-beta (2026-11-22)

Chi tiết: `docs/release-notes/0.1.7-beta.md`.
- Trackpad đa chạm, nút chuột vật lý, bàn phím ảo và Text Composer (tiếng Việt), Numpad, điều khiển trình chiếu (iOS và Android).
- Codec HEVC trên host và viewer; thanh Sidecar Quick Dock (Spotlight, Mission Control, App Switcher, Hoàn tác, khoá/mở khoá).
- AI Co-Pilot Help (`agent.help`): agent AI xin người dùng trợ giúp, viewer hiện banner; truyền tệp đầu tiên (`file.offer`/`file.data`, lưu `~/Downloads/Xdesk`, kiểm SHA-256); USB tunnel Android.

## 0.1.6-beta (2026-11-20)

Android: chạm 2 lần để mở bàn phím (tắt được trong Cài đặt chuột), nút "Xong" ẩn bàn phím, dòng đang gõ không bị che; giải thích khi không cập nhật được vì khác chữ ký. Chi tiết: `docs/release-notes/0.1.6-beta.md`.

## 0.1.5-beta (2026-11-20)

- Ghép đôi bằng mã 6 số phải bấm "Khớp" ở cả hai máy; chỉ lưu Mac sau khi người dùng xác nhận.
- Agent AI (MCP): không mất kết quả xin quyền khi duyệt chậm hơn 10 giây; sửa giới hạn số kết nối đồng thời.
- Chạm trực tiếp: vuốt một ngón cuộn có quán tính, nhấn giữ kéo thả/chuột phải; click chính xác hơn khi tay rung. Chi tiết: `docs/release-notes/0.1.5-beta.md`.

## 0.1.4-beta (2026-11-20)

Mac thêm tiếng Anh (Cài đặt › Chung › Ngôn ngữ); hộp thoại cập nhật đúng ngôn ngữ và không bị bảng menu che; bảng thanh menu có số thiết bị đang xem, phiên bản app, nút "Dừng chia sẻ" rõ hơn.

## 0.1.3-beta (2026-11-20)

- Android và iPhone dùng chung giao diện (bố cục, chữ, biểu tượng, màu); mục "Giao diện" ở Cài đặt: Tối (mặc định) | Sáng | Theo hệ thống; Android có nền cửa sổ tối ngay lúc khởi động.
- Bảng token dùng chung `docs/design-tokens.md`; màu primary/accent/warning/danger của Android khớp `BrandPalette.swift`.
- Mac: bảng thanh menu tự đóng khi mở cửa sổ khác; nút "Mở lại Xdesk" sau khi cấp quyền Ghi màn hình.

## 0.1.2-beta (2026-11-20)

Giao diện mới trên cả ba app (bảng điều khiển thanh menu, Cài đặt 5 mục, quét QR và nhiều máy Mac trên điện thoại); ghép đôi QR hoạt động khi mạng nhà chặn máy nói chuyện với nhau (dùng Tailscale); sửa luật mặc định "Cấm" cho Terminal, Keychain Access, Cài đặt hệ thống với agent AI có thể bị ghi đè.

## 0.1.1-beta (2026-11-19)

Chế độ "Bản sao" là mặc định (3 kiểu vừa khung); cửa sổ Mac tự co giãn vừa màn hình điện thoại; bàn phím mới và cài đặt chuột (chạm trực tiếp/con trỏ, cuộn tự nhiên, nhấn giữ chuột phải); nút điều khiển nổi; Mac tự cập nhật; Android tự cập nhật, sửa văng khi mở, giảm giật trên chip Unisoc.

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
