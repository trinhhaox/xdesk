#!/usr/bin/env bash
# Dùng: tools/release-mac.sh <phiên-bản> [số-build] [--publish]
#   phiên-bản  CFBundleShortVersionString, ví dụ 0.1.0-beta
#   số-build   CFBundleVersion, số nguyên tăng dần (mặc định: số commit của git). Sparkle so sánh theo số này.
#   --publish  tạo GitHub pre-release + đẩy appcast.xml lên trinhhaox/xdesk-releases
# Ký + notarize bằng Developer ID quản lý trên đám mây của Xcode (không cần chứng thư cục bộ).
set -euo pipefail

VERSION="${1:?Thiếu phiên bản, ví dụ 0.1.0-beta}"
BUILD=""
PUBLISH=0
for arg in "${@:2}"; do
    case "$arg" in
        --publish) PUBLISH=1 ;;
        *) BUILD="$arg" ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="4DU4BTV46U"
REPO="trinhhaox/xdesk-releases"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD)}"
OUT="$ROOT/build/release/$VERSION"
DMG="$OUT/Xdesk-$VERSION.dmg"
POLL_SECONDS=15
POLL_ATTEMPTS=80
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Volumes/XcodeExternal/Applications/Xcode.app/Contents/Developer}"

[[ "$BUILD" =~ ^[0-9]+$ ]] || { echo "Số build phải là số nguyên: $BUILD" >&2; exit 1; }
if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
    echo "Cảnh báo: cây làm việc còn thay đổi chưa commit; bản phát hành nên build từ commit sạch." >&2
fi
step() { printf '[%3ds] %s\n' "$SECONDS" "$*"; }

rm -rf "$OUT"
mkdir -p "$OUT"
step "Phiên bản $VERSION (build $BUILD), thư mục $OUT"

step "Tạo project và archive Release"
(cd "$ROOT/apple/mac-app" && xcodegen generate >/dev/null)
xcodebuild archive -project "$ROOT/apple/mac-app/Xdesk.xcodeproj" -scheme Xdesk-mac -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$OUT/Xdesk.xcarchive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates \
    > "$OUT/archive.log" 2>&1 || { tail -25 "$OUT/archive.log" >&2; exit 1; }

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>signingStyle</key><string>automatic</string>
<key>destination</key><string>upload</string>
</dict></plist>
PLIST

step "Ký Developer ID và gửi Apple notarize"
xcodebuild -exportArchive -archivePath "$OUT/Xdesk.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -exportPath "$OUT/upload" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
    || { tail -25 "$OUT/export.log" >&2; exit 1; }

step "Chờ Apple notarize"
for ((attempt = 1; attempt <= POLL_ATTEMPTS; attempt++)); do
    if xcodebuild -exportNotarizedApp -archivePath "$OUT/Xdesk.xcarchive" -exportPath "$OUT/notarized" \
        > "$OUT/notarized.log" 2>&1; then break; fi
    if ((attempt == POLL_ATTEMPTS)); then
        echo "Notarize chưa xong sau $((POLL_SECONDS * POLL_ATTEMPTS))s." >&2
        tail -25 "$OUT/notarized.log" >&2
        exit 1
    fi
    sleep "$POLL_SECONDS"
done
APP="$OUT/notarized/Xdesk.app"

step "Kiểm tra chữ ký, staple, Gatekeeper"
xcrun stapler staple "$APP" >/dev/null
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"
SIGNER="$(grep -m1 '^Authority=' <<<"$SIGN_INFO")"
[[ "$SIGNER" == "Authority=Developer ID Application: Trinh Hao ($TEAM_ID)" ]] \
    || { echo "Chữ ký không đúng Developer ID mong đợi: $SIGNER" >&2; exit 1; }
spctl -a -vvv -t install "$APP" 2>&1 | tee "$OUT/spctl-app.txt"
grep -q "Notarized Developer ID" "$OUT/spctl-app.txt" \
    || { echo "App chưa được Gatekeeper chấp nhận là Notarized Developer ID." >&2; exit 1; }
for key in CFBundleShortVersionString CFBundleVersion; do
    echo "$key = $(/usr/libexec/PlistBuddy -c "Print $key" "$APP/Contents/Info.plist")"
done

step "Dựng DMG (không ký, như Xmac: chữ ký Developer ID đám mây chỉ cấp cho app)"
"$ROOT/tools/make-dmg.sh" "$APP" "$DMG"

step "Tạo appcast.xml (ký EdDSA bằng khoá trong Keychain, tài khoản xdesk)"
SPARKLE_BIN="$("$ROOT/tools/sparkle-tools.sh")"
NOTES="$ROOT/docs/release-notes/$VERSION.md"
[[ -f "$NOTES" ]] && cp "$NOTES" "$OUT/Xdesk-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" --account xdesk --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://github.com/$REPO" -o "$OUT/appcast.xml" "$OUT" > "$OUT/appcast.log" 2>&1 \
    || { tail -20 "$OUT/appcast.log" >&2; exit 1; }
"$ROOT/tools/verify-appcast.sh" "$OUT/appcast.xml" "$DMG"

if ((PUBLISH)); then
    step "Phát hành lên $REPO (pre-release)"
    BODY="$OUT/release-body.md"
    {
        [[ -f "$NOTES" ]] && cat "$NOTES"
        printf '\n---\nBuild %s, %s\n' "$BUILD" "$(xcodebuild -version | tr '\n' ' ')"
    } > "$BODY"
    if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
        gh release upload "v$VERSION" "$DMG" --repo "$REPO" --clobber
    else
        gh release create "v$VERSION" "$DMG" --repo "$REPO" --title "Xdesk $VERSION" \
            --notes-file "$BODY" --prerelease --latest=false
    fi
    "$ROOT/tools/publish-appcast.sh" "$OUT/appcast.xml" "$VERSION"
fi
step "Xong: $DMG"
