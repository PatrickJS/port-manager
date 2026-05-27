#!/usr/bin/env bash
set -euo pipefail

LABEL="dev.patrickjs.PortManager"
APP_NAME="PortManager"
LAUNCHER_NAME="PortManagerLauncher"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
LAUNCHER_BINARY="$APP_BUNDLE/Contents/MacOS/$LAUNCHER_NAME"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOGS_DIR="$HOME/Library/Logs"
PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
GUI_DOMAIN="gui/$(id -u)"

# Stop the old always-running helper before replacing dist/PortManager.app.
/bin/launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true
pkill -x "$LAUNCHER_NAME" >/dev/null 2>&1 || true

"$ROOT_DIR/script/build_and_run.sh" --stage

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOGS_DIR"
: >"$LOGS_DIR/PortManager.launchd.out.log"
: >"$LOGS_DIR/PortManager.launchd.err.log"

cat >"$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$LAUNCHER_BINARY</string>
    <string>$APP_BUNDLE</string>
    <string>$APP_NAME</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOGS_DIR/PortManager.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOGS_DIR/PortManager.launchd.err.log</string>
</dict>
</plist>
PLIST
/bin/launchctl bootstrap "$GUI_DOMAIN" "$PLIST_PATH"
/bin/launchctl kickstart -k "$GUI_DOMAIN/$LABEL" >/dev/null 2>&1 || true

echo "Installed $LABEL for $APP_BUNDLE"
