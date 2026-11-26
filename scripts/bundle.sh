#!/usr/bin/env bash
# Builds a universal release binary and wraps it into build/MacResourceMonitor.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/MacResourceMonitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MonitorApp" "$APP/Contents/MacOS/MonitorApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
strip -x "$APP/Contents/MacOS/MonitorApp"

codesign --force --options runtime --sign - "$APP"
codesign --verify --verbose "$APP"

du -sh "$APP"
echo "Built $APP"
