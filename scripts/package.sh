#!/usr/bin/env bash
# Packages build/MacResourceMonitor.app into a .zip (used by Sparkle) and a .dmg (for people).
# Usage: scripts/package.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: $0 <version>}"
APP="build/MacResourceMonitor.app"
ZIP="build/MacResourceMonitor-$VERSION.zip"
DMG="build/MacResourceMonitor-$VERSION.dmg"
[[ -d "$APP" ]] || { echo "$APP not found; run scripts/bundle.sh first" >&2; exit 1; }

rm -f "$ZIP" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/MacResourceMonitor.app"
ln -s /Applications "$STAGING/Applications"
# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3; do
    if hdiutil create -volname "Mac Resource Monitor" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"; then
        break
    fi
    [[ $attempt == 3 ]] && exit 1
    sleep 5
done

ls -lh "$ZIP" "$DMG"
