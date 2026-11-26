#!/usr/bin/env bash
# Prints the CHANGELOG.md section for a version, without its heading.
# Usage: scripts/release-notes.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: $0 <version>}"
NOTES="$(awk -v heading="## [$VERSION]" '
    index($0, heading) == 1 { found = 1; next }
    found && /^## \[/ { exit }
    found && /^\[[^]]+\]: / { exit }
    found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [[ -z "${NOTES//[[:space:]]/}" ]]; then
    echo "CHANGELOG.md has no entries for $VERSION; add a \"## [$VERSION] - YYYY-MM-DD\" section." >&2
    exit 1
fi
printf '%s\n' "$NOTES"
