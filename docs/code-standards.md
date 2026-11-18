# Chuẩn mã nguồn

## Công cụ

- Xcode 27.1 (`DEVELOPER_DIR=/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer`), Swift 6.4.
- XcodeGen 2.46.0 (`brew install xcodegen`); file `.xcodeproj` được sinh ra, không commit.
- JDK 17, Gradle 8.10.2 (wrapper), AGP 8.5.2, Kotlin 2.0.20, Compose BOM 2024.09.03.
- Android: minSdk 31, compileSdk/targetSdk 34 (SDK máy dev đang có), applicationId `vn.xox.xdesk`.
- `swiftformat` và `ktlint` là tùy chọn: `make lint` bỏ qua nếu chưa cài.

## Quy tắc chung

- File dưới 200 dòng; tách module khi vượt.
- Tên file không phải Swift/Kotlin dùng kebab-case; Swift/Kotlin theo tên kiểu (PascalCase).
- Thư viện dùng chung Apple nằm trong SPM `apple/Packages/XdeskKit` (XdeskWire, XdeskCrypto, XdeskTransport, XdeskMedia, XdeskInput, XdeskAgent); test bằng `swift test`.
- Android tách module `:wire :crypto :transport :media :app`; logic thuần (wire, crypto) test JVM không cần thiết bị.
- Không thêm thư viện mạng bên thứ ba ở v1.
- Không commit chứng chỉ, keystore, `local.properties`; keystore release để ngoài repo (`~/.xdesk-keys/`).
- Mọi mã tuân thủ `clean-room-policy.md`.

## Commit

Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
