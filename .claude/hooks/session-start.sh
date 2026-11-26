#!/bin/bash
# Claude Code cloud sessions run on Linux without Swift: install it so `make lint` works
# before pushing. Skips quickly once the toolchain is in place.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
    exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}"
scripts/setup-linux-dev.sh
