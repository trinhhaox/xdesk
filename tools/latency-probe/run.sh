#!/usr/bin/env bash
# Đo glass-to-glass qua loopback trên một Mac: host+viewer trong cùng app Xdesk (Debug), probe vẽ đồng hồ trên màn hình ảo,
# chụp màn hình chính nhiều lần (viewer + lớp phủ nằm ở đó) rồi giải mã. Cần quyền Ghi màn hình cho terminal chạy script.
set -euo pipefail
cd "$(dirname "$0")"
N="${1:-40}"
APP="$(ls -d /Volumes/XcodeExternal/DerivedData/Xdesk-*/Build/Products/Debug/Xdesk.app | head -1)"
OUT="$(mktemp -d)"
swift build -c release >/dev/null
PROBE=.build/release/latency-probe
"$APP/Contents/MacOS/Xdesk" --auto-host --auto-connect 127.0.0.1:47800 --latency-overlay --quit-after $((N / 2 + 25)) >"$OUT/app.log" 2>&1 &
APP_PID=$!
trap 'kill $APP_PID 2>/dev/null || true; kill ${PROBE_PID:-} 2>/dev/null || true' EXIT
sleep 6
"$PROBE" clock --seconds $((N / 2 + 15)) &
PROBE_PID=$!
sleep 4
for i in $(seq 1 "$N"); do screencapture -x -D 1 "$OUT/shot-$i.png"; sleep 0.3; done
"$PROBE" measure "$OUT"/shot-*.png | tail -n "$((N + 1))"
echo "ảnh chụp: $OUT"
