#!/usr/bin/env bash
# Build, package, and launch the macOS app bundle.
#
# Usage: ./script/build_and_run.sh [run|--debug|--logs|--telemetry|--verify|--release|--clean]
#
# Modes:
#   run (default)  Build, package, and open the app
#   --debug        Open the built binary under lldb
#   --logs         Stream unified logs filtered to the running process
#   --telemetry    Stream unified logs filtered to the app's subsystem
#   --verify       Build, launch, and confirm the process is alive
#   --release      Build a release configuration bundle (slower, optimised binary)
#   --clean        Remove .build and dist before building
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WorkflowGenerator"
BUNDLE_ID="com.local.WorkflowGenerator"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

if [ "$MODE" = "--clean" ] || [ "${CLEAN:-0}" = "1" ]; then
  echo "▶ cleaning .build and dist"
  rm -rf "$ROOT_DIR/.build" "$DIST_DIR"
fi

if [ "$MODE" = "--release" ]; then
  SWIFT_CONFIG=(--configuration release)
else
  SWIFT_CONFIG=()
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build --package-path "$ROOT_DIR" ${SWIFT_CONFIG[@]+"${SWIFT_CONFIG[@]}"}
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" ${SWIFT_CONFIG[@]+"${SWIFT_CONFIG[@]}"} --show-bin-path)/$APP_NAME"

if [ ! -x "$BUILD_BINARY" ]; then
  echo "✗ build did not produce $BUILD_BINARY" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
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
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run|--release|--clean)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--release|--clean]" >&2
    exit 2
    ;;
esac
