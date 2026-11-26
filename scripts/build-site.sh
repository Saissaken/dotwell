#!/usr/bin/env bash
# Assembles the project page (https://saissaken.github.io/dotwell/) into build/site.
# The screenshots and the icon come from the same files the README and the app use, so the page never
# drifts from them. Requires Python 3 with Pillow (for the icon sizes).
# Usage: scripts/build-site.sh [output-dir]
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/site}"

rm -rf "$OUT"
mkdir -p "$OUT/images"
cp site/*.html site/*.css site/*.js "$OUT/"
cp docs/images/popover-*.png "$OUT/images/"
python3 - "$OUT/images" <<'PY'
import sys
from PIL import Image

icon = Image.open("Resources/AppIcon.png")
for size in (64, 256):
    icon.resize((size, size), Image.LANCZOS).save(f"{sys.argv[1]}/icon-{size}.png", optimize=True)
PY
touch "$OUT/.nojekyll"
echo "Built $OUT"
