#!/usr/bin/env python3
"""Turns the output of run.sh into a Markdown report comparing a pull request with main.

    report.py <out-dir> [--base base] [--head head]

Writes <out-dir>/report.md and <out-dir>/flags.json. Never fails the build: budgets are soft limits,
so anything over budget or clearly worse than main is flagged for a person to decide on.
"""

import json
import statistics
import sys
from pathlib import Path

MARKER = "<!-- dotwell-perf-report -->"

# key, label, unit, decimals, budget (popover closed only), noise floor (absolute, relative).
# A change only counts as a regression when it clears both floors and the ranges of the two builds
# don't overlap, because CI runners are shared virtual machines and their numbers wander.
METRICS = {
    "closed": [
        ("cpu_percent", "CPU (% of one core)", "%", 3, 0.2, (0.03, 0.15)),
        ("rss_mb", "Memory, resident", " MB", 1, 25, (1.5, 0.08)),
        ("footprint_mb", "Memory, footprint", " MB", 1, None, (1.5, 0.08)),
        ("wakeups_per_s", "Wakeups", "/s", 2, 2, (0.3, 0.15)),
        ("idle_wakeups_per_s", "Idle wakeups", "/s", 2, None, (0.3, 0.15)),
        ("energy_mw", "Energy", " mW", 1, None, (1.0, 0.15)),
    ],
    "open": [
        ("cpu_percent", "CPU (% of one core)", "%", 2, None, (0.3, 0.15)),
        ("footprint_mb", "Memory, footprint", " MB", 1, None, (2.0, 0.08)),
        ("wakeups_per_s", "Wakeups", "/s", 1, None, (2.0, 0.15)),
    ],
}


def load(out):
    samples = {}
    for line in (out / "samples.jsonl").read_text().splitlines():
        if line.strip():
            row = json.loads(line)
            samples.setdefault((row["label"], row["mode"]), []).append(row["metrics"])
    sizes_path = out / "sizes.json"
    sizes = json.loads(sizes_path.read_text()) if sizes_path.exists() else {}
    return samples, sizes


def fmt(value, unit, decimals):
    return f"{value:.{decimals}f}{unit}"


def stats(rows, key):
    values = [row[key] for row in rows if key in row]
    if not values:
        return None
    return {"median": statistics.median(values), "min": min(values), "max": max(values), "n": len(values)}


def cell(s, unit, decimals):
    if s is None:
        return "n/a"
    text = fmt(s["median"], unit, decimals)
    if s["n"] > 1:
        text += f" <sub>({s['min']:.{decimals}f}–{s['max']:.{decimals}f})</sub>"
    return text


def compare(base, head, floors):
    """Returns 'worse', 'better' or None."""
    if base is None or head is None:
        return None
    delta = head["median"] - base["median"]
    abs_floor, rel_floor = floors
    if abs(delta) < abs_floor or abs(delta) < rel_floor * max(base["median"], 1e-9):
        return None
    if delta > 0 and head["min"] > base["max"]:
        return "worse"
    if delta < 0 and head["max"] < base["min"]:
        return "better"
    return None


def section(title, mode, samples, base_label, head_label, flags):
    base_rows = samples.get((base_label, mode), [])
    head_rows = samples.get((head_label, mode), [])
    if not head_rows:
        return []
    has_base = bool(base_rows)
    lines = [f"**{title}**", ""]
    header = "| Metric | main | This PR | Change | Budget |" if has_base else "| Metric | This PR | Budget |"
    lines += [header, "|---|" + "---:|" * (header.count("|") - 2)]
    for key, label, unit, decimals, budget, floors in METRICS[mode]:
        b, h = stats(base_rows, key), stats(head_rows, key)
        if h is None:
            continue
        # Virtual machines report no energy; skip the row instead of showing zeros.
        if key == "energy_mw" and h["max"] == 0 and (b is None or b["max"] == 0):
            continue
        notes = []
        if budget is not None and h["median"] > budget:
            notes.append("⚠️ over budget")
            flags.append(f"{title}: {label} is {fmt(h['median'], unit, decimals)}, over the {budget}{unit} budget")
        verdict = compare(b, h, floors)
        if verdict == "worse":
            notes.append("🔺 worse than main")
            flags.append(
                f"{title}: {label} went from {fmt(b['median'], unit, decimals)} to {fmt(h['median'], unit, decimals)}"
            )
        elif verdict == "better":
            notes.append("🟢 better")
        budget_text = f"< {budget}{unit}" if budget is not None else ""
        if has_base:
            change = "" if b is None else f"{h['median'] - b['median']:+.{decimals}f}{unit}"
            if notes:
                change += " " + " ".join(notes)
            lines.append(f"| {label} | {cell(b, unit, decimals)} | {cell(h, unit, decimals)} | {change} | {budget_text} |")
        else:
            lines.append(f"| {label} | {cell(h, unit, decimals)} {' '.join(notes)} | {budget_text} |")
    if not has_base:
        lines += ["", "_main can't open the popover on its own yet, so there is nothing to compare with._"]
    return lines + [""]


def size_section(sizes, base_label, head_label):
    head = sizes.get(head_label)
    if not head:
        return []
    base = sizes.get(base_label)
    lines = ["**App size** (informational)", "", "| | main | This PR | Change |", "|---|---:|---:|---:|"]
    for key, label in [("bundle_mb", "Dotwell.app"), ("binary_mb", "Executable")]:
        b = base[key] if base else None
        h = head[key]
        lines.append(
            f"| {label} | {'n/a' if b is None else f'{b:.2f} MB'} | {h:.2f} MB | "
            f"{'' if b is None else f'{h - b:+.2f} MB'} |"
        )
    return lines + [""]


def main():
    args = sys.argv[1:]
    out = Path(args[0])
    base_label = args[args.index("--base") + 1] if "--base" in args else "base"
    head_label = args[args.index("--head") + 1] if "--head" in args else "head"
    samples, sizes = load(out)
    flags = []
    rounds = max((len(v) for v in samples.values()), default=0)

    body = []
    body += section("Popover closed", "closed", samples, base_label, head_label, flags)
    body += section("Popover open", "open", samples, base_label, head_label, flags)
    body += size_section(sizes, base_label, head_label)

    if not samples:
        summary = "⚠️ The measurement didn't run. See the workflow log."
        flags.append("the measurement didn't produce any samples")
    elif flags:
        summary = "⚠️ **Needs a look.** This is a soft limit and doesn't block the merge:\n\n" + "\n".join(
            f"- {f}" for f in flags
        )
    else:
        summary = "✅ Within budget and no measurable change from main."

    report = [
        MARKER,
        "## Performance check",
        "",
        summary,
        "",
        *body,
        "<details><summary>How this is measured</summary>",
        "",
        f"Each build runs on its own on the CI's macOS runner, {rounds} times, alternating with main. "
        "After a warm-up, CPU time, wakeups and energy come from the kernel's counters for the process "
        "(`proc_pid_rusage`, the source Activity Monitor uses), and memory is sampled every second. "
        "Values are medians, with the range across runs in small print. A change is only called out when "
        "it's bigger than the runner's noise and the ranges don't overlap. Budgets come from the README and "
        "apply with the popover closed. The runner is a virtual machine, so absolute numbers are indicative; "
        "the comparison with main is what matters. Script: `scripts/perf/run.sh`.",
        "",
        "</details>",
        "",
    ]
    (out / "report.md").write_text("\n".join(report))
    (out / "flags.json").write_text(json.dumps({"flagged": bool(flags), "items": flags}, indent=2))
    for flag in flags:
        print(f"::warning title=Performance::{flag}")
    print("\n".join(report))


if __name__ == "__main__":
    main()
