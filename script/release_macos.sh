#!/usr/bin/env bash
# Package a release-config .app bundle into a distributable, unsigned DMG.
#
# Usage: ./script/release_macos.sh <version>
#   e.g. ./script/release_macos.sh v0.1.0
#
# Output:
#   dist/WorkflowGenerator-<version>-macos.dmg
#   dist/WorkflowGenerator-<version>-macos.dmg.sha256
#
# Notes:
#   - DMG is unsigned. Users will hit Gatekeeper on first launch; release
#     notes must document the workaround (right-click → Open).
#   - Constants below MUST match script/build_and_run.sh so dev and release
#     produce the same app identity.
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "usage: $0 <version>" >&2
  echo "       version should look like v0.1.0" >&2
  exit 2
fi

VERSION="$1"
VERSION_NUMBER="${VERSION#v}"

APP_NAME="WorkflowGenerator"
BUNDLE_ID="com.local.WorkflowGenerator"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$DIST_DIR/_dmg_stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

DMG_NAME="$APP_NAME-$VERSION-macos.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
SHA_PATH="$DMG_PATH.sha256"
VOLUME_NAME="$APP_NAME $VERSION"

echo "▶ clean .build and dist"
rm -rf "$ROOT_DIR/.build" "$DIST_DIR"
mkdir -p "$STAGE_DIR"

echo "▶ swift build --configuration release"
swift build --package-path "$ROOT_DIR" --configuration release

BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" --configuration release --show-bin-path)/$APP_NAME"
if [ ! -x "$BUILD_BINARY" ]; then
  echo "✗ build did not produce $BUILD_BINARY" >&2
  exit 1
fi

echo "▶ assemble $APP_NAME.app"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION_NUMBER</string>
  <key>CFBundleVersion</key>
  <string>$VERSION_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▶ hdiutil create $DMG_NAME"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH" >/dev/null

echo "▶ shasum"
(
  cd "$DIST_DIR"
  shasum -a 256 "$DMG_NAME" >"$SHA_PATH"
)

rm -rf "$STAGE_DIR"

echo
echo "✓ done"
echo "  DMG    : $DMG_PATH"
echo "  SHA256 : $(cut -d' ' -f1 "$SHA_PATH")"
echo "  size   : $(du -h "$DMG_PATH" | cut -f1)"
