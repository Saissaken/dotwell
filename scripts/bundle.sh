#!/usr/bin/env bash
# Builds a universal release binary and wraps it into build/MacResourceMonitor.app.
#
# Environment:
#   VERSION        marketing version (CFBundleShortVersionString), defaults to Info.plist
#   BUILD          build number (CFBundleVersion, compared by Sparkle), defaults to Info.plist
#   SIGN_IDENTITY  codesign identity, defaults to "-" (ad-hoc). A Developer ID identity also
#                  enables the hardened runtime and secure timestamps needed for notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="build/MacResourceMonitor.app"
BIN="$APP/Contents/MacOS/MonitorApp"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MonitorApp" "$BIN"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -n "${VERSION:-}" ]] && plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
[[ -n "${BUILD:-}" ]] && plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"

# Embed Sparkle (ditto keeps the framework's symlinks intact).
SPARKLE_XCFRAMEWORK="$(find .build/artifacts -type d -name Sparkle.xcframework -print -quit)"
[[ -n "$SPARKLE_XCFRAMEWORK" ]] || { echo "Sparkle.xcframework not found in .build/artifacts" >&2; exit 1; }
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_XCFRAMEWORK/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"

strip -x "$BIN"
if ! otool -l "$BIN" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN"
fi

# Sign inside-out. Sparkle's helpers are re-signed with our identity: its installer only talks
# to an app signed by the same team, and ad-hoc signatures have no team.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_FLAGS=(--force --sign - --timestamp=none)
else
    SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY" --options runtime --timestamp)
fi
SPARKLE_B="$FRAMEWORK/Versions/B"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_B/XPCServices/Installer.xpc"
codesign "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements "$SPARKLE_B/XPCServices/Downloader.xpc"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_B/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$FRAMEWORK"
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

du -sh "$APP"
echo "Built $APP ($(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"))"
