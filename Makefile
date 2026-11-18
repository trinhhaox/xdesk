export DEVELOPER_DIR ?= /Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer
export JAVA_HOME ?= /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home

.PHONY: bootstrap gen build-mac build-ios test-apple test-android lint

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

test-android:
	cd android && ./gradlew test

lint:
	@if command -v swiftformat >/dev/null; then swiftformat --lint apple; else echo "Bỏ qua: chưa cài swiftformat"; fi
	@if command -v ktlint >/dev/null; then cd android && ktlint; else echo "Bỏ qua: chưa cài ktlint"; fi
