#!/usr/bin/env bash
# Dùng: tools/publish-appcast.sh <appcast.xml> <phiên-bản>
# Ghi appcast.xml lên nhánh main của trinhhaox/xdesk-releases qua GitHub Contents API (không cần clone).
# URL ổn định cho Sparkle: https://raw.githubusercontent.com/trinhhaox/xdesk-releases/main/appcast.xml
set -euo pipefail

APPCAST="${1:?Thiếu appcast.xml}"
VERSION="${2:?Thiếu phiên bản}"
REPO="trinhhaox/xdesk-releases"

SHA="$(gh api "repos/$REPO/contents/appcast.xml" --jq .sha 2>/dev/null || true)"
ARGS=(-X PUT "repos/$REPO/contents/appcast.xml" -f message="release: appcast $VERSION" -f content="$(base64 -i "$APPCAST")")
[[ -n "$SHA" ]] && ARGS+=(-f sha="$SHA")
gh api "${ARGS[@]}" --jq '.content.html_url'
