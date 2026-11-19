# Quy trình phát hành Xdesk

Phát hành ngoài App Store: DMG (Mac, cập nhật qua Sparkle) và APK (Android). Mã nguồn ở repo riêng tư `trinhhaox/xdesk`; bản phát hành nằm ở repo công khai `trinhhaox/xdesk-releases` (chỉ chứa DMG, APK và `appcast.xml`).

## Nơi đặt appcast và lý do

Sparkle đọc `https://raw.githubusercontent.com/trinhhaox/xdesk-releases/main/appcast.xml` (đặt trong `SUFeedURL`).

- Không dùng `releases/latest/download/appcast.xml` vì GitHub bỏ qua bản pre-release khi tính "latest": 0.1.0-beta là pre-release nên URL đó sẽ trả 404.
- URL raw theo nhánh `main` luôn ổn định, phục vụ qua HTTPS. Bộ đệm của raw khoảng 5 phút: bản mới có thể chậm vài phút mới hiện ra.
- Enclosure trỏ tới asset của GitHub Release: `https://github.com/trinhhaox/xdesk-releases/releases/download/v<phiên bản>/Xdesk-<phiên bản>.dmg`.
- Appcast chỉ giữ mục của bản mới nhất; Sparkle chỉ cần bản mới nhất để cập nhật.

## Phiên bản

- `CFBundleShortVersionString` (`MARKETING_VERSION`): chuỗi hiển thị, ví dụ `0.1.0-beta`.
- `CFBundleVersion` (`CURRENT_PROJECT_VERSION`): số nguyên tăng dần. **Sparkle so sánh theo số này**, không theo chuỗi hiển thị, nên hậu tố `-beta` không gây lỗi so sánh. Mặc định `release-mac.sh` dùng số commit của git; truyền tay làm tham số thứ hai nếu cần.
- Android: `versionName` trong `android/app/build.gradle.kts`; `versionCode` phải tăng mỗi bản phát hành.
- Giữ nguyên bundle id `vn.xox.xdesk` và team `4DU4BTV46U`, nếu không quyền TCC (Ghi màn hình, Trợ năng) và dữ liệu ghép đôi bị mất khi cập nhật.

## Khoá và nơi lưu

| Khoá | Vị trí | Sao lưu |
|---|---|---|
| EdDSA Sparkle (riêng tư) | Keychain đăng nhập, tài khoản `xdesk` (mục "ed25519 / xdesk") | `~/.xdesk/sparkle/2.10.1/bin/generate_keys --account xdesk -x <tệp>` rồi cất tệp vào kho mật khẩu hoặc ổ mã hoá, xoá bản tạm |
| Khoá công khai Sparkle | `SUPublicEDKey` trong `apple/mac-app/project.yml` | đã nằm trong repo |
| Keystore Android | `~/.xdesk/keys/xdesk-release.jks` (alias `xdesk`) | sao chép tệp ra nơi an toàn |
| Mật khẩu keystore | Keychain, dịch vụ `xdesk-android-release` | `security find-generic-password -s xdesk-android-release -a xdesk -w`, cất cùng keystore |

Mất khoá EdDSA: người dùng cũ không nhận được cập nhật tự động nữa (phải cài tay bản có khoá mới). Mất keystore Android: không thể cập nhật đè APK đã cài (chữ ký khác). Khôi phục khoá EdDSA từ bản sao: `generate_keys --account xdesk -f <tệp>`.

## Phát hành Mac

```sh
export DEVELOPER_DIR=/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer
tools/release-mac.sh 0.1.0-beta            # build, notarize, DMG, appcast (chưa đăng)
tools/release-mac.sh 0.1.0-beta --publish  # thêm: GitHub pre-release + đẩy appcast.xml
```

Các bước của script: archive Release, `xcodebuild -exportArchive` (method `developer-id`, destination `upload`) để Xcode ký bằng Developer ID quản lý trên đám mây và gửi Apple notarize, chờ `-exportNotarizedApp`, staple, kiểm `spctl -a -vvv -t install` phải ra "Notarized Developer ID", dựng DMG, tạo `appcast.xml` bằng `generate_appcast` và kiểm độ dài/chữ ký EdDSA bằng `tools/verify-appcast.sh`.

Máy này không có chứng thư Developer ID cục bộ và không có mật khẩu notarytool; chứng thư đám mây không hiện trong `security find-identity`. DMG để không ký (như Xmac) vì chữ ký đám mây chỉ cấp khi export app; app bên trong đã notarize và staple nên mở DMG vẫn qua Gatekeeper.

Ghi chú phát hành: `docs/release-notes/<phiên bản>.md` (Markdown, tiếng Việt), được nhúng vào appcast và nội dung GitHub Release cùng phiên bản Xcode.

## Phát hành Android

```sh
tools/release-android.sh            # build + ký + apksigner verify
tools/release-android.sh --publish  # đính APK vào release v<versionName> (chạy sau release-mac.sh --publish)
```

Lần chạy đầu tự tạo keystore. Gradle đọc `XDESK_KEYSTORE_PATH`, `XDESK_KEYSTORE_PASSWORD`, `XDESK_KEY_ALIAS` do script đặt từ Keychain; không có biến này thì bản release không được ký.

## Kiểm tra trước khi đăng

- `make test-apple`, `make test-mac`, `make test-android` xanh.
- `stapler validate` và `spctl -a -vvv -t install Xdesk.app` đạt trên app trong thư mục `build/release/<phiên bản>/notarized/` và trên app trong DMG đã mount.
- `curl -I https://raw.githubusercontent.com/trinhhaox/xdesk-releases/main/appcast.xml` trả 200.
- `apksigner verify --print-certs` ra đúng chứng chỉ `CN=Xdesk, O=XOX, C=VN`.

## Thử cập nhật 0.1.0 → 0.1.1 (chưa làm trong bản đầu)

1. Cài 0.1.0-beta từ DMG vào `/Applications` trên máy sạch (hoặc tài khoản macOS khác), cấp Ghi màn hình + Trợ năng.
2. Tăng phiên bản: `tools/release-mac.sh 0.1.1-beta --publish` (số build tự tăng theo số commit; phải lớn hơn bản đang cài).
3. Đợi khoảng 5 phút cho bộ đệm raw, mở Xdesk 0.1.0-beta, chọn "Kiểm tra cập nhật…", chấp nhận cài.
4. Xác nhận app khởi động lại thành 0.1.1-beta và Ghi màn hình/Trợ năng vẫn còn quyền, thiết bị đã ghép vẫn còn.
5. Với Android: cài đè APK 0.1.1 (`versionCode` cao hơn) bằng `adb install -r` và kiểm tra dữ liệu ghép đôi còn nguyên.

Thử với bản Debug mà không đụng app đang chạy: đặt biến `XDESK_APPCAST_URL` trỏ tới một appcast khác khi mở bản Debug (chỉ có tác dụng ở cấu hình Debug).

## Khi có sự cố

Sparkle không hạ cấp: phát bản sửa với số build cao hơn. Muốn gỡ một bản lỗi, sửa lại `appcast.xml` (qua `tools/publish-appcast.sh`) và giữ DMG bản trước trên Releases để người dùng cài tay.

## Ghi chú xuất khẩu mã hoá và quyền riêng tư

- `ITSAppUsesNonExemptEncryption = true` cho Mac và iOS: Xdesk tự cài đặt giao thức Noise (ChaChaPoly, X25519) trên CryptoKit, không phải mã hoá chuẩn do hệ điều hành cung cấp sẵn nên không thuộc diện miễn trừ. Phát hành Developer ID/APK không bị ảnh hưởng; trước khi dùng TestFlight/App Store phải khai báo tuân thủ xuất khẩu.
- `PrivacyInfo.xcprivacy` khai báo `UserDefaults` (CA92.1) và `SystemBootTime` (35F9.1), không theo dõi, không thu thập dữ liệu.
