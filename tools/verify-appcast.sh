#!/usr/bin/env bash
# Dùng: tools/verify-appcast.sh <appcast.xml> <Xdesk-X.dmg>
# Kiểm tra mục appcast khớp DMG: độ dài, chữ ký EdDSA (khoá trong Keychain, tài khoản xdesk), URL HTTPS.
set -euo pipefail

APPCAST="${1:?Thiếu appcast.xml}"
DMG="${2:?Thiếu DMG}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_BIN="$("$ROOT/tools/sparkle-tools.sh")"

ATTR() { xmllint --xpath "string(//enclosure/@$1)" "$APPCAST"; }
SIZE_APPCAST="$(ATTR length)"
SIZE_DMG="$(stat -f %z "$DMG")"
SIGNATURE="$(xmllint --xpath 'string(//enclosure/@*[local-name()="edSignature"])' "$APPCAST")"
URL="$(ATTR url)"

[[ "$URL" == https://* ]] || { echo "URL enclosure không phải HTTPS: $URL" >&2; exit 1; }
[[ "$SIZE_APPCAST" == "$SIZE_DMG" ]] || { echo "Độ dài lệch: appcast=$SIZE_APPCAST dmg=$SIZE_DMG" >&2; exit 1; }
[[ -n "$SIGNATURE" ]] || { echo "Appcast thiếu sparkle:edSignature" >&2; exit 1; }
"$SPARKLE_BIN/sign_update" --account xdesk --verify "$DMG" "$SIGNATURE" >/dev/null 2>&1 \
    || { echo "Chữ ký EdDSA không khớp DMG" >&2; exit 1; }
echo "Appcast hợp lệ: $URL ($SIZE_DMG byte, chữ ký EdDSA khớp)"
