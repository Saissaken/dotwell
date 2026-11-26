#!/usr/bin/env bash
# Packages build/Dotwell.app into:
#   build/Dotwell-<version>.zip  the update archive Sparkle downloads
#   build/Dotwell.dmg            the drag-to-Applications disk image people download
# The disk image name has no version so releases/latest/download/Dotwell.dmg always works.
# Usage: scripts/package.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: $0 <version>}"
APP="build/Dotwell.app"
ZIP="build/Dotwell-$VERSION.zip"
DMG="build/Dotwell.dmg"
DMGBUILD_VERSION="1.6.7"
[[ -d "$APP" ]] || { echo "$APP not found; run scripts/bundle.sh first" >&2; exit 1; }

rm -f "$ZIP" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Window background with a Retina representation.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swift scripts/dmg-background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff"

# dmgbuild writes the Finder layout (.DS_Store) directly, so it works headless on CI, unlike
# scripting Finder. It is installed into a private virtualenv on first use.
VENV=".build/dmgbuild-$DMGBUILD_VERSION"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet "dmgbuild==$DMGBUILD_VERSION"
fi
# hdiutil occasionally fails with "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3; do
    if "$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" -D icon=build/AppIcon.icns \
        -D background="$WORK/background.tiff" "Dotwell" "$DMG"; then
        break
    fi
    [[ $attempt == 3 ]] && exit 1
    sleep 5
done

ls -lh "$ZIP" "$DMG"
