#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dockerd"
DIST="dist"
APP="$DIST/$APP_NAME.app"
BUILD_TMP=".build/release-bundle"
LOCAL_SIGN_NAME="${LOCAL_SIGN_NAME:-Dockerd Local Signing}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
UNIVERSAL="${UNIVERSAL:-1}"

ARCH_ARGS=()
if [ "$UNIVERSAL" = "1" ]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER), release"
if ! swift build -c release "${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}"; then
  if [ "$UNIVERSAL" = "1" ]; then
    echo "==> Universal build failed; falling back to the host architecture"
    ARCH_ARGS=()
    swift build -c release
  else
    exit 1
  fi
fi
BIN_DIR="$(swift build -c release "${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP" "$BUILD_TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_TMP"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Rendering icon"
swift scripts/make-icon.swift "$BUILD_TMP/AppIcon.iconset"
iconutil -c icns "$BUILD_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

SIGN_LABEL="$SIGN_IDENTITY"
if [ -z "$SIGN_IDENTITY" ]; then
  LOCAL_HASH="$(security find-identity -p codesigning 2>/dev/null | grep -F "\"$LOCAL_SIGN_NAME\"" | awk '{print $2}' | head -n 1 || true)"
  if [ -n "$LOCAL_HASH" ]; then
    SIGN_IDENTITY="$LOCAL_HASH"
    SIGN_LABEL="$LOCAL_SIGN_NAME (local)"
  else
    SIGN_IDENTITY="-"
    SIGN_LABEL="ad-hoc; Accessibility must be re-granted after each build (see docs/SIGNING.md)"
  fi
fi

echo "==> Signing: $SIGN_LABEL"
case "$SIGN_IDENTITY" in
  -)
    codesign --force --sign - --identifier me.santoshpanna.Dockerd "$APP" ;;
  "Developer ID Application"*)
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp --identifier me.santoshpanna.Dockerd "$APP" ;;
  *)
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --identifier me.santoshpanna.Dockerd "$APP" ;;
esac
codesign --verify --strict --verbose=2 "$APP"

echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "==> Built $APP"
