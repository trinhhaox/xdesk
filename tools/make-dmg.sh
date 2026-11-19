#!/usr/bin/env bash
# Dùng: tools/make-dmg.sh <Xdesk.app> <đầu-ra.dmg>
# Dựng DMG có nền thương hiệu, biểu tượng ổ đĩa và lối tắt Applications.
# Bố cục cửa sổ đặt qua Finder (AppleScript); nếu Finder không cho phép thì DMG vẫn dùng được, chỉ mất bố cục.
set -euo pipefail

APP="${1:?Thiếu đường dẫn Xdesk.app}"
OUT="${2:?Thiếu đường dẫn DMG đầu ra}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET_SRC="$ROOT/apple/mac-app/Sources/Assets.xcassets/AppIcon.appiconset"
VOLNAME="Xdesk"

if [[ -e "/Volumes/$VOLNAME" ]]; then
    echo "Đã có ổ đĩa /Volumes/$VOLNAME đang gắn; hãy eject rồi chạy lại." >&2
    exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/xdesk-dmg.XXXXXX")"
MOUNT="/Volumes/$VOLNAME"
cleanup() {
    hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Xdesk.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck "$ROOT/tools/dmg/background.png" "$ROOT/tools/dmg/background@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null

# Biểu tượng ổ đĩa: ghép .icns từ bộ icon của app.
ICONSET="$WORK/Xdesk.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    cp "$ICONSET_SRC/icon_${size}.png" "$ICONSET/icon_${size}x${size}.png"
    cp "$ICONSET_SRC/icon_${size}@2x.png" "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$STAGE/.VolumeIcon.icns"

RW="$WORK/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" -noverify >/dev/null
SetFile -a C "$MOUNT" 2>/dev/null || echo "Cảnh báo: không đặt được cờ biểu tượng ổ đĩa (SetFile)." >&2

# Finder chỉ thấy ổ đĩa theo tên, nên gắn ở /Volumes/Xdesk (không dùng -nobrowse).
if ! osascript >/dev/null 2>&1 <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 500}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Xdesk.app" of container window to {170, 190}
        set position of item "Applications" of container window to {430, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA
then
    echo "Cảnh báo: Finder không đặt được bố cục DMG (cần quyền Automation); DMG vẫn dùng được." >&2
fi

sync
hdiutil detach "$MOUNT" >/dev/null
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
echo "DMG: $OUT"
