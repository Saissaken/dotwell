#!/usr/bin/env bash
# Launches one or more builds of Dotwell in turn and measures each with the popover closed and open.
#
#   scripts/perf/run.sh <out-dir> <label>=<path/to/Dotwell.app> [<label>=<path> ...]
#
# Builds are interleaved round by round (base, head, head, base, ...) so a noisy stretch on the
# machine hits all of them alike. Writes <out-dir>/samples.jsonl (one line per measurement) and
# <out-dir>/sizes.json, plus a screenshot per build with the popover open.
#
# Environment: ROUNDS (3), WARMUP (20 s), CLOSED_SECONDS (60), OPEN_SECONDS (30).
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT="$1"
shift
ROUNDS="${ROUNDS:-3}"
WARMUP="${WARMUP:-20}"
CLOSED_SECONDS="${CLOSED_SECONDS:-60}"
OPEN_SECONDS="${OPEN_SECONDS:-30}"
mkdir -p "$OUT"
: > "$OUT/samples.jsonl"

MEASURE="$OUT/measure"
swiftc -O scripts/perf/measure.swift -o "$MEASURE"

# Same state as an installed app that has been set up already: no "move to Applications" or
# update prompts, no login item, and no Sparkle checks adding network noise to the numbers.
DOMAIN=com.saissaken.Dotwell
defaults write "$DOMAIN" suppressMoveToApplications -bool true
defaults write "$DOMAIN" didRegisterLoginItem -bool true
defaults write "$DOMAIN" SUEnableAutomaticChecks -bool false
defaults write "$DOMAIN" SUHasLaunchedBefore -bool true

LABELS=()
APPS=()
for pair in "$@"; do
    LABELS+=("${pair%%=*}")
    APPS+=("${pair#*=}")
done

# One measurement: launch, let it settle, measure, quit.
measure() {
    local label="$1" app="$2" mode="$3" round="$4" seconds="$5"
    local binary="$app/Contents/MacOS/Dotwell" args=()
    [[ "$mode" == open ]] && args=(-PerfOpenPopoverOnLaunch YES)
    pkill -x Dotwell 2> /dev/null || true
    "$binary" ${args[@]+"${args[@]}"} > "$OUT/$label-$mode-$round.log" 2>&1 &
    local pid=$!
    sleep "$WARMUP"
    if [[ "$mode" == open && "$round" == 1 ]]; then
        screencapture -x "$OUT/$label-open.png" || true
    fi
    local result
    if result="$("$MEASURE" "$pid" "$seconds")"; then
        printf '{"label":"%s","mode":"%s","round":%s,"metrics":%s}\n' "$label" "$mode" "$round" "$result" \
            >> "$OUT/samples.jsonl"
        echo "$label $mode round $round: $result"
    else
        echo "::warning::$label $mode round $round: measurement failed (see $label-$mode-$round.log)"
    fi
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
}

for ((round = 1; round <= ROUNDS; round++)); do
    order=("${!LABELS[@]}")
    # Reverse the order every other round.
    if ((round % 2 == 0)); then
        reversed=()
        for ((i = ${#order[@]} - 1; i >= 0; i--)); do reversed+=("${order[i]}"); done
        order=("${reversed[@]}")
    fi
    for i in "${order[@]}"; do
        measure "${LABELS[i]}" "${APPS[i]}" closed "$round" "$CLOSED_SECONDS"
        # Builds from before this check existed can't open the popover on their own.
        if grep -q PerfOpenPopoverOnLaunch "${APPS[i]}/Contents/MacOS/Dotwell"; then
            measure "${LABELS[i]}" "${APPS[i]}" open "$round" "$OPEN_SECONDS"
        fi
    done
done

{
    echo "{"
    for i in "${!LABELS[@]}"; do
        app="${APPS[i]}"
        bundle_kb="$(du -sk "$app" | cut -f1)"
        binary_bytes="$(stat -f %z "$app/Contents/MacOS/Dotwell")"
        [[ $i -gt 0 ]] && echo ","
        awk -v l="${LABELS[i]}" -v kb="$bundle_kb" -v b="$binary_bytes" \
            'BEGIN { printf "\"%s\":{\"bundle_mb\":%.3f,\"binary_mb\":%.3f}", l, kb / 1024, b / 1048576 }'
    done
    echo "}"
} > "$OUT/sizes.json"
cat "$OUT/sizes.json"
