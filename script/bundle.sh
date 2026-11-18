#!/usr/bin/env bash
# Builds TokenSpeed and assembles dist/TokenSpeed.app.
# usage: script/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="TokenSpeed"
BUNDLE_ID="com.tokenspeed.TokenSpeed"
MIN_SYSTEM_VERSION="14.0"
VERSION="${TOKENSPEED_VERSION:-1.0}"

case "$CONFIG" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"

cd "$ROOT_DIR"
swift build -c "$CONFIG"
BUILD_BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

mkdir -p "$APP_MACOS"
install -m 755 "$BUILD_BINARY" "$APP_MACOS/$APP_NAME"

cat >"$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# An ad-hoc signature gives the bundle a stable identity for Login Items.
codesign --force --sign - "$APP_BUNDLE" >/dev/null
echo "$APP_BUNDLE"
