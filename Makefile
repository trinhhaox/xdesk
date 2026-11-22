export DEVELOPER_DIR ?= /Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer
export JAVA_HOME ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

.PHONY: bootstrap gen build-mac build-ios test-apple test-mac test-ios test-android lint

bootstrap:
	@command -v xcodegen >/dev/null || { echo "Thiếu xcodegen: brew install xcodegen"; exit 1; }
	@test -f android/local.properties || echo "sdk.dir=/Volumes/XcodeExternal/Android/sdk" > android/local.properties
	@echo "Bootstrap xong."

gen:
	cd apple/mac-app && xcodegen generate
	cd apple/ios-app && xcodegen generate

build-mac: gen
	xcodebuild -project apple/mac-app/Xdesk.xcodeproj -scheme Xdesk-mac -configuration Debug build

build-ios: gen
	xcodebuild -project apple/ios-app/XdeskIOS.xcodeproj -scheme Xdesk-ios -configuration Debug \
		-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

test-apple:
	cd apple/Packages/XdeskKit && swift test

test-mac: gen
	xcodebuild test -project apple/mac-app/Xdesk.xcodeproj -scheme Xdesk-mac -destination 'platform=macOS'

# Chạy test thật trên Simulator. Chọn máy: make test-ios IOS_SIM_ID=<udid>; mặc định lấy iPhone đầu tiên còn dùng được.
IOS_SIM_ID := $(or $(IOS_SIM_ID),$(shell xcrun simctl list devices available 2>/dev/null | grep -m1 'iPhone' | grep -Eo '[0-9A-F-]{36}'))

test-ios: gen
	@test -n "$(IOS_SIM_ID)" || { echo "Không tìm thấy iPhone Simulator: tạo bằng Xcode hoặc truyền IOS_SIM_ID=<udid>"; exit 1; }
	xcodebuild test -project apple/ios-app/XdeskIOS.xcodeproj -scheme Xdesk-ios -configuration Debug \
		-destination 'platform=iOS Simulator,id=$(IOS_SIM_ID)' CODE_SIGNING_ALLOWED=NO

test-android:
	cd android && ./gradlew test

lint:
	@if command -v swiftformat >/dev/null; then swiftformat --lint apple; else echo "Bỏ qua: chưa cài swiftformat"; fi
	@if command -v ktlint >/dev/null; then cd android && ktlint; else echo "Bỏ qua: chưa cài ktlint"; fi
