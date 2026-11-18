# Phase 10 — Đóng gói, ký, notarize, Sparkle, phát hành

## Context
- Phụ thuộc: 03–09. Team Developer ID `4DU4BTV46U`; notarize qua Xcode cloud signing như các app Mac khác (Xmac). Build cần `DEVELOPER_DIR` trên ổ XcodeExternal.
- Phát hành NGOÀI App Store: DMG + Sparkle (Mac), TestFlight/ad-hoc (iOS), APK sideload (Android).

## Overview
- Ưu tiên: P2 · pending · 3d

## Key insights
- Mac app không sandbox, hardened runtime; entitlement tối thiểu (không cần `com.apple.security.cs.disable-library-validation` nếu không nạp plugin). Private API CGVirtualDisplay không ảnh hưởng notarization (chỉ App Review mới chặn).
- Sparkle 2: khoá EdDSA (`generate_keys`) lưu Keychain máy build, `SUPublicEDKey` trong Info.plist; appcast trên GitHub Releases hoặc trang `xdesk.xox.vn` (hỏi user). Bật `SUVerifyUpdateBeforeExtraction`.
- Quyền TCC (Screen Recording, Accessibility) gắn với chữ ký + bundle id → giữ cố định giữa các bản, nếu không người dùng phải cấp lại mỗi lần cập nhật.
- iOS: TestFlight cần App Store Connect record; App Review sau này có thể không chấp nhận app có MCP/điều khiển? — receiver iOS không chứa private API nên khả thi; vẫn rà theo `docs/apple-app-review-pre-submission-process.md` của user trước khi nộp.
- Android: ký APK release bằng keystore ngoài repo; `versionCode` tăng mỗi bản; Play Store để sau.

## Requirements
- `tools/release-mac.sh <version>`: build Release → ký Developer ID → notarize (`notarytool` hoặc cloud signing) → staple → DMG (nền + icon brand riêng) → ký DMG → `generate_appcast` → `gh release create`.
- `tools/release-android.sh`: assembleRelease, `apksigner verify`, đính kèm GitHub Release.
- `tools/release-ios.sh`: archive + upload TestFlight (khi user muốn).
- Build tái lập: ghi version Xcode/Gradle vào release notes.

## Architecture
```
git tag vX.Y.Z → release-mac.sh → Xdesk-X.Y.Z.dmg (notarized, stapled) → appcast.xml (EdDSA) → GitHub Release
                → release-android.sh → xdesk-X.Y.Z.apk
App Mac (Sparkle) ── kiểm appcast mỗi 24h ──► tải, xác minh EdDSA + Developer ID ─► cài
```

## Related code files (tạo)
- `tools/release-mac.sh`, `tools/make-dmg.sh`, `tools/release-android.sh`, `tools/release-ios.sh`, `apple/mac-app/Xdesk.entitlements`, `apple/mac-app/Sources/App/UpdaterController.swift`, `docs/release-process.md`, `docs/project-changelog.md`.

## Implementation steps
1. Thêm Sparkle 2 qua SPM, UpdaterController + menu "Kiểm tra cập nhật".
2. Script release Mac; chạy thử bản 0.1.0-beta, kiểm `spctl -a -vvv -t install Xdesk.app` và `stapler validate`.
3. Cập nhật thử 0.1.0 → 0.1.1 qua Sparkle trên máy sạch (hoặc user macOS khác), kiểm quyền TCC còn giữ.
4. APK release cài JP1.
5. (Tuỳ chọn) TestFlight nội bộ iOS.
6. Viết docs release + changelog.

## Todo
- [ ] Sparkle + UpdaterController
- [ ] release-mac.sh + DMG
- [ ] Thử cập nhật 0.1.0→0.1.1
- [ ] release-android.sh
- [ ] TestFlight (tuỳ chọn)
- [ ] docs/release-process.md

## Success criteria
- `spctl` báo "accepted, source=Notarized Developer ID"; mở DMG trên máy khác không có cảnh báo Gatekeeper.
- Sparkle cập nhật thành công, Screen Recording + Accessibility không phải cấp lại.
- `apksigner verify --print-certs` đúng chứng chỉ; cài đè bản cũ không mất dữ liệu ghép đôi.

## Risks
| Rủi ro | K×T | Giảm thiểu |
|---|---|---|
| Notarization từ chối (thiếu hardened runtime/timestamp) | Thấp×TB | `--options runtime --timestamp`, đọc log `notarytool log` |
| Lộ khoá EdDSA Sparkle → cập nhật giả | Thấp×Cao | khoá chỉ trong Keychain máy build, backup ngoại tuyến |
| Đổi bundle id/chữ ký → mất TCC + ghép đôi | TB×Cao | chốt bundle id ở phase 01, không đổi |

## Security
- Không commit `.p12`, keystore, khoá EdDSA; script đọc từ Keychain/ENV.
- Appcast phục vụ qua HTTPS.

## Rollback
- Sparkle không hạ cấp: phát bản sửa với version cao hơn; gỡ appcast entry lỗi; giữ DMG bản trước để người dùng cài tay.
