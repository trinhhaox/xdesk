# Phase 01 — Nền móng monorepo, thương hiệu, chính sách clean-room

## Context
- Repo mới: `/Users/trinhhao/Antigravity/xdesk` (chỉ README.md, .gitignore, chưa có commit).
- Xcode 27 ở `/Volumes/XcodeExternal/Applications/Xcode.app` → mọi script build đặt `DEVELOPER_DIR=/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer`.
- Plan tổng: [plan.md](plan.md)

## Overview
- Ưu tiên: P1 · Trạng thái: done (trừ cài APK lên JP1: thiết bị offline) · Effort: 1d
- Dựng khung thư mục, toolchain, CI lint/test cục bộ, tài liệu clean-room, bộ nhận diện riêng.

## Key insights
- XcodeGen (`project.yml`) cho target app → diff dễ đọc, tránh xung đột `.pbxproj`; thư viện dùng chung là SPM local package → test bằng `swift test` không cần mở Xcode.
- Một app Mac cho cả Host và Viewer: giảm 1 lần ký/notarize/Sparkle, tái dùng decode.
- Android tách module Gradle theo trách nhiệm để file < 200 dòng và test JVM thuần (wire, crypto) không cần thiết bị.

## Requirements
- Chức năng: `make bootstrap`, `make test-apple`, `make test-android` chạy xanh với project rỗng.
- Phi chức năng: kebab-case cho file không phải Swift/Kotlin; Swift PascalCase theo type; Kotlin PascalCase class; file < 200 dòng.

## Architecture — bố cục monorepo
```
xdesk/
  protocol/
    spec/            # xdesk-wire-v1-overview.md, framing.md, messages.md, crypto-handshake.md, media-packets.md
    test-vectors/    # *.json + *.hex dùng chung Swift/Kotlin
  apple/
    Packages/XdeskKit/   # SPM: XdeskWire, XdeskCrypto, XdeskTransport, XdeskMedia, XdeskInput, XdeskAgent
    mac-app/project.yml  # app "Xdesk" (menu bar, Host + Viewer)
    ios-app/project.yml  # "Xdesk" iOS/iPadOS (Viewer)
  android/
    settings.gradle.kts  # :wire :crypto :transport :media :app
  tools/             # build-*.sh, release-*.sh, latency-probe/
  docs/              # clean-room-policy.md, code-standards.md, system-architecture.md, brand-guide.md
```
- Công nghệ: Swift 6 + SwiftUI/AppKit (menu bar `MenuBarExtra`), Network.framework, ScreenCaptureKit, VideoToolbox, CryptoKit; Kotlin + Jetpack Compose (UI đơn giản), MediaCodec, `java.net` DatagramChannel/Socket hoặc NsdManager; không thêm thư viện mạng bên thứ ba ở v1.
- Android minSdk 31 (có X25519 `XDH` + ChaCha20-Poly1305 sẵn trong Conscrypt) — cần xác nhận lại ở phase 06.

## Related code files
- Tạo: cây trên, `Makefile`, `apple/Packages/XdeskKit/Package.swift`, 2 `project.yml`, `android/*.gradle.kts`, `docs/clean-room-policy.md`, `docs/brand-guide.md`, `docs/code-standards.md`, `tools/build-mac.sh`.
- Sửa: `.gitignore` (thêm `apple/**/*.xcodeproj`, `.build/`, `android/**/build/`), `README.md`.

## Implementation steps
1. Cài `xcodegen` (brew) — ghi version vào `docs/code-standards.md`.
2. Tạo SPM `XdeskKit` với 6 target rỗng + test target mỗi cái.
3. Tạo `mac-app/project.yml`: bundle id `<chờ chốt>.xdesk`, LSUIElement=YES, hardened runtime, team 4DU4BTV46U, App Sandbox TẮT (cần CGEvent/AX/private API).
4. Tạo `ios-app/project.yml`: iPhone + iPad, `NSLocalNetworkUsageDescription`, `NSBonjourServices=[_xdesk._tcp]`.
5. Tạo Android Gradle multi-module, Compose app rỗng, chạy `./gradlew test`.
6. Viết `docs/clean-room-policy.md`: danh sách cấm (đường dẫn meowdisplay, binary Yosei), checklist PR ("không tên/chuỗi/asset/định dạng vay mượn"), cách xử lý nếu lỡ đọc (ghi lại, người khác viết phần đó).
7. Viết `docs/brand-guide.md`: logo Xdesk riêng (họ "X" của Xmac/Xdrive), bảng màu, giọng văn tiếng Việt; không mô phỏng UI/icon app tham khảo.
8. `Makefile`: `bootstrap`, `gen` (xcodegen), `test-apple`, `test-android`, `lint` (swiftformat --lint, ktlint).

## Todo
- [x] Cây thư mục + Makefile
- [x] XdeskKit SPM + test rỗng xanh
- [x] project.yml Mac + iOS, build Debug được
- [x] Android multi-module, `./gradlew test` xanh
- [x] docs/clean-room-policy.md, brand-guide.md, code-standards.md
- [ ] Commit đầu tiên (chỉ khi user yêu cầu)

## Success criteria
- `make test-apple && make test-android` exit 0 trên máy dev.
- `make gen && xcodebuild -scheme Xdesk-mac build` thành công; app menu bar hiện icon Xdesk.
- APK debug cài lên JP1: `adb -s 100.76.122.48:5555 install -r android/app/build/outputs/apk/debug/app-debug.apk` mở được.

## Risks
| Rủi ro | Khả năng × Tác động | Giảm thiểu |
|---|---|---|
| Xcode 27 + XcodeGen chưa tương thích định dạng project mới | Thấp × TB | Ghim version XcodeGen; fallback `objectVersion` cũ |
| Bundle id/brand chưa chốt → đổi sau tốn công ký lại | TB × TB | Hỏi user trước khi tạo provisioning |

## Security
- Không commit cert/keystore; Android release keystore để ngoài repo (`~/.xdesk-keys/`), `.gitignore` chặn `*.jks`, `*.p12`.

## Next steps
- Phase 02 đặc tả giao thức.
