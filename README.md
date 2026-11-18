# Xdesk

Dùng iPhone, iPad, Android hoặc một Mac khác làm màn hình phụ và điều khiển Mac; kèm máy chủ MCP cho agent AI điều khiển Mac.

## Cấu trúc

```
protocol/   đặc tả giao thức và test vector dùng chung
apple/      XdeskKit (SPM), mac-app (menu bar), ios-app
android/    Gradle đa module :wire :crypto :transport :media :app
tools/      script build/phát hành
docs/       chính sách clean-room, hướng dẫn thương hiệu, chuẩn mã
plans/      kế hoạch triển khai
```

## Thiết lập

Yêu cầu: macOS + Xcode 27, `xcodegen`, JDK 17, Android SDK.

```sh
make bootstrap   # kiểm tra xcodegen, ghi android/local.properties
make gen         # sinh file .xcodeproj cho Mac và iOS
```

Mặc định `DEVELOPER_DIR` trỏ tới Xcode trên ổ ngoài và `JAVA_HOME` tới openjdk@17 của Homebrew; ghi đè bằng biến môi trường nếu khác.

## Lệnh make

| Lệnh | Việc |
|---|---|
| `make test-apple` | `swift test` cho XdeskKit |
| `make test-android` | `./gradlew test` |
| `make build-mac` | build Debug app Mac |
| `make build-ios` | build Debug app iOS cho Simulator |
| `make lint` | swiftformat/ktlint nếu đã cài |

APK debug: `cd android && ./gradlew :app:assembleDebug`.

## Chính sách

Dự án viết độc lập theo [clean-room](docs/clean-room-policy.md). Thương hiệu: [brand-guide](docs/brand-guide.md). Chuẩn mã: [code-standards](docs/code-standards.md).
