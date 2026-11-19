#!/usr/bin/env bash
# Dùng: tools/release-android.sh [--publish]
# Dựng APK release, ký bằng ~/.xdesk/keys/xdesk-release.jks, kiểm tra bằng apksigner.
# Lần đầu tự tạo keystore với mật khẩu ngẫu nhiên lưu trong Keychain (dịch vụ xdesk-android-release).
# --publish: đính APK vào GitHub Release v<versionName> của trinhhaox/xdesk-releases (phải có sẵn, chạy sau release-mac.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="trinhhaox/xdesk-releases"
KEY_DIR="$HOME/.xdesk/keys"
KEYSTORE="$KEY_DIR/xdesk-release.jks"
KEY_ALIAS="xdesk"
KEYCHAIN_SERVICE="xdesk-android-release"
SDK_DIR="${ANDROID_HOME:-/Volumes/XcodeExternal/Android/sdk}"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"

PUBLISH=0
[[ "${1:-}" == "--publish" ]] && PUBLISH=1

read_password() { security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEY_ALIAS" -w 2>/dev/null; }

if [[ ! -f "$KEYSTORE" ]]; then
    if read_password >/dev/null; then
        echo "Keychain đã có mật khẩu '$KEYCHAIN_SERVICE' nhưng thiếu $KEYSTORE; khôi phục keystore từ bản sao lưu trước." >&2
        exit 1
    fi
    echo "Tạo keystore mới tại $KEYSTORE"
    mkdir -p "$KEY_DIR"
    chmod 700 "$KEY_DIR"
    XDESK_KEYSTORE_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=\n')"
    export XDESK_KEYSTORE_PASSWORD
    keytool -genkeypair -keystore "$KEYSTORE" -alias "$KEY_ALIAS" -keyalg RSA -keysize 4096 -validity 10950 \
        -storepass:env XDESK_KEYSTORE_PASSWORD -keypass:env XDESK_KEYSTORE_PASSWORD \
        -dname "CN=Xdesk, O=XOX, C=VN" >/dev/null
    chmod 600 "$KEYSTORE"
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEY_ALIAS" -w "$XDESK_KEYSTORE_PASSWORD" \
        -j "Mật khẩu keystore $KEYSTORE"
fi

XDESK_KEYSTORE_PASSWORD="$(read_password)" || { echo "Không đọc được mật khẩu từ Keychain ($KEYCHAIN_SERVICE)." >&2; exit 1; }
export XDESK_KEYSTORE_PASSWORD XDESK_KEYSTORE_PATH="$KEYSTORE" XDESK_KEY_ALIAS="$KEY_ALIAS"

(cd "$ROOT/android" && ./gradlew --console=plain :app:assembleRelease 2>&1 | tail -8)

VERSION="$(sed -n 's/.*versionName = "\(.*\)".*/\1/p' "$ROOT/android/app/build.gradle.kts")"
BUILT="$ROOT/android/app/build/outputs/apk/release/app-release.apk"
[[ -f "$BUILT" ]] || { echo "Không thấy APK release tại $BUILT (đã ký chưa?)." >&2; exit 1; }
OUT="$ROOT/build/release/$VERSION"
mkdir -p "$OUT"
APK="$OUT/xdesk-$VERSION.apk"
cp "$BUILT" "$APK"

APKSIGNER="$(ls -d "$SDK_DIR"/build-tools/*/apksigner | sort -V | tail -1)"
"$APKSIGNER" verify --verbose --print-certs "$APK" | tee "$OUT/apksigner.txt" | grep -E "^(Verifies|Verified using v2|V2 Signer: certificate (DN|SHA-256))"
echo "APK: $APK ($(stat -f %z "$APK") byte)"

if ((PUBLISH)); then
    gh release upload "v$VERSION" "$APK" --repo "$REPO" --clobber
fi
