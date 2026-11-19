#!/usr/bin/env bash
# Dùng: tools/publish-android-manifest.sh <android-update.json> [--force]
# Ghi android-update.json lên nhánh main của trinhhaox/xdesk-releases (cạnh appcast.xml) qua GitHub Contents API.
# URL cho app: https://raw.githubusercontent.com/trinhhaox/xdesk-releases/main/android-update.json
# Chặn đăng khi: APK chưa có trên GitHub Release v<versionName>, hoặc versionCode thấp hơn bản đang đăng (trừ khi --force).
set -euo pipefail

MANIFEST="${1:?Thiếu android-update.json}"
FORCE=0
[[ "${2:-}" == "--force" ]] && FORCE=1
REPO="trinhhaox/xdesk-releases"
command -v jq >/dev/null || { echo "Thiếu jq (brew install jq)." >&2; exit 1; }

VERSION="$(jq -er .versionName "$MANIFEST")"
CODE="$(jq -er .versionCode "$MANIFEST")"
ASSET="$(basename "$(jq -er .apkUrl "$MANIFEST")")"
gh release view "v$VERSION" --repo "$REPO" --json assets --jq '.assets[].name' | grep -qxF "$ASSET" \
    || { echo "Release v$VERSION chưa có asset $ASSET; chạy release-android.sh --publish trước." >&2; exit 1; }

SHA="$(gh api "repos/$REPO/contents/android-update.json" --jq .sha 2>/dev/null || true)"
if [[ -n "$SHA" && $FORCE -eq 0 ]]; then
    LIVE="$(gh api "repos/$REPO/contents/android-update.json" -H "Accept: application/vnd.github.raw" | jq -er .versionCode)"
    ((CODE >= LIVE)) || { echo "versionCode $CODE thấp hơn bản đang đăng ($LIVE); dùng --force nếu cố ý." >&2; exit 1; }
fi
ARGS=(-X PUT "repos/$REPO/contents/android-update.json" -f message="release: android-update $VERSION" -f content="$(base64 -i "$MANIFEST")")
[[ -n "$SHA" ]] && ARGS+=(-f sha="$SHA")
gh api "${ARGS[@]}" --jq '.content.html_url'
