#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="PortManager"
LAUNCHER_NAME="PortManagerLauncher"
BUNDLE_ID="dev.patrickjs.PortManager"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
LAUNCHER_BINARY="$APP_MACOS/$LAUNCHER_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
GUI_DOMAIN="gui/$(id -u)"
PNPM_PATH="$(command -v pnpm)"
NODE_PATH="$(command -v node)"
CLI_ENTRYPOINT="$ROOT_DIR/packages/cli/bin/port-manager.js"
CLI_PATH="$(dirname "$NODE_PATH"):$(dirname "$PNPM_PATH"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

LAUNCH_AGENT_WAS_LOADED=0
if /bin/launchctl print "$GUI_DOMAIN/$BUNDLE_ID" >/dev/null 2>&1; then
  LAUNCH_AGENT_WAS_LOADED=1
  /bin/launchctl bootout "$GUI_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || true
fi
pkill -x "$LAUNCHER_NAME" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR" --product "$APP_NAME"
swift build --package-path "$PACKAGE_DIR" --product "$LAUNCHER_NAME"
BUILD_DIR="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
BUILD_LAUNCHER="$BUILD_DIR/$LAUNCHER_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_LAUNCHER" "$LAUNCHER_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$LAUNCHER_BINARY"

node -e 'console.log(JSON.stringify({ repoRoot: process.argv[1], pnpmPath: process.argv[2], nodePath: process.argv[3], pathEnvironment: process.argv[4], cliEntrypointPath: process.argv[5] }, null, 2))' \
  "$ROOT_DIR" "$PNPM_PATH" "$NODE_PATH" "$CLI_PATH" "$CLI_ENTRYPOINT" >"$APP_RESOURCES/PortManagerConfig.json"

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
  /usr/bin/open "$APP_BUNDLE" "$@"
}

start_launch_agent_if_needed() {
  if [[ "$LAUNCH_AGENT_WAS_LOADED" != "1" || ! -f "$LAUNCH_AGENT_PLIST" ]]; then
    return 1
  fi
  /bin/launchctl bootstrap "$GUI_DOMAIN" "$LAUNCH_AGENT_PLIST" >/dev/null 2>&1 || return 1
  /bin/launchctl kickstart -k "$GUI_DOMAIN/$BUNDLE_ID" >/dev/null 2>&1 || true
  return 0
}

case "$MODE" in
  --stage|stage)
    ;;
  run)
    start_launch_agent_if_needed || open_app
    ;;
  --dock|dock)
    start_launch_agent_if_needed || true
    open_app --args --dock
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    start_launch_agent_if_needed || open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    start_launch_agent_if_needed || open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    start_launch_agent_if_needed || open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--stage|--dock|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
