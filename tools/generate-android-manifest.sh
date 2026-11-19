#!/usr/bin/env bash
# Dùng: tools/generate-android-manifest.sh <apk> [đầu-ra.json]
# Sinh android-update.json (versionCode, versionName, apkUrl, sha256, size, minSdk, releaseNotes, publishedAt) cho app Android.
# Phiên bản đọc từ android/app/build.gradle.kts; ghi chú lấy từ docs/release-notes/<phiên bản>.android.md, nếu thiếu thì <phiên bản>.md.
# Không đăng gì; đăng bằng tools/publish-android-manifest.sh. Không chứa bí mật.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="trinhhaox/xdesk-releases"
APK="${1:?Thiếu đường dẫn APK}"
GRADLE="$ROOT/android/app/build.gradle.kts"
[[ -f "$APK" ]] || { echo "Không thấy APK: $APK" >&2; exit 1; }
command -v jq >/dev/null || { echo "Thiếu jq (brew install jq)." >&2; exit 1; }

gradle_value() { sed -n "s/.*$1 = \"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$GRADLE" | head -1; }
VERSION_NAME="$(gradle_value versionName)"
VERSION_CODE="$(gradle_value versionCode)"
MIN_SDK="$(gradle_value minSdk)"
[[ "$VERSION_CODE" =~ ^[0-9]+$ && "$MIN_SDK" =~ ^[0-9]+$ && -n "$VERSION_NAME" ]] \
    || { echo "Không đọc được versionName/versionCode/minSdk từ $GRADLE." >&2; exit 1; }

OUT="${2:-$(dirname "$APK")/android-update.json}"
NOTES_FILE="$ROOT/docs/release-notes/$VERSION_NAME.android.md"
[[ -f "$NOTES_FILE" ]] || NOTES_FILE="$ROOT/docs/release-notes/$VERSION_NAME.md"
NOTES=""
# Bỏ dòng tiêu đề "## ..." đầu tiên; app hiển thị văn bản thuần nên giữ nguyên phần còn lại.
[[ -f "$NOTES_FILE" ]] && NOTES="$(sed '1{/^#/d;}' "$NOTES_FILE" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | sed '/./,$!d')"

jq -n \
    --argjson versionCode "$VERSION_CODE" --arg versionName "$VERSION_NAME" \
    --arg apkUrl "https://github.com/$REPO/releases/download/v$VERSION_NAME/$(basename "$APK")" \
    --arg sha256 "$(shasum -a 256 "$APK" | cut -d' ' -f1)" --argjson size "$(stat -f %z "$APK")" \
    --argjson minSdk "$MIN_SDK" --arg releaseNotes "$NOTES" --arg publishedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{versionCode:$versionCode, versionName:$versionName, apkUrl:$apkUrl, sha256:$sha256, size:$size, minSdk:$minSdk, releaseNotes:$releaseNotes, publishedAt:$publishedAt}' > "$OUT"
echo "Đã tạo $OUT"
