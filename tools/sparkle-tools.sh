#!/usr/bin/env bash
# Tải (một lần) bộ công cụ dòng lệnh của Sparkle và in đường dẫn thư mục bin.
# Phiên bản phải khớp với `exactVersion` của Sparkle trong apple/mac-app/project.yml.
set -euo pipefail

SPARKLE_VERSION="2.10.1"
DIR="$HOME/.xdesk/sparkle/$SPARKLE_VERSION"

if [[ ! -x "$DIR/bin/generate_appcast" ]]; then
    mkdir -p "$DIR"
    ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/sparkle.XXXXXX")"
    trap 'rm -f "$ARCHIVE"' EXIT
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o "$ARCHIVE"
    tar -xf "$ARCHIVE" -C "$DIR" ./bin
fi
echo "$DIR/bin"
