# Requirements

Status: **draft v0.1** (2026-11-26).

Items marked **[ASSUMPTION]** are defaults chosen by the maintainers that are cheap to change.
Items marked **[OPEN]** are waiting on a product decision and are not built until decided.

## 1. Goal

A native macOS menu bar app that is always running, tells you at a glance whether your Mac is healthy,
and opens a compact popover with simple charts of the critical resources when clicked.
The primary use case is **watching network latency (ping)**.

## 2. Top priority: minimal resource usage

When a feature competes with resource usage, resource usage wins. Target budget, measured on Apple Silicon
with the popover closed:

| Metric | Target |
|---|---|
| Average CPU | < 0.2 % of one core |
| Memory (RSS) | < 25 MB |
| Wakeups per second | < 2 |
| Activity Monitor "Energy Impact" | Low / ~0 |
| App bundle size | < 5 MB |

With the popover open, more is allowed (redrawing charts), but usage must return to budget once it closes.
Every release measures these numbers and records them in its pull request.

## 3. Features

### 3.1 Always running
- R1. Icon in the right-hand side of the menu bar. No Dock icon, no main window.
- R2. Launches at login, enabled by default, with an option to turn it off.
- R3. No self-relaunch after a crash in v1. **[ASSUMPTION]**

### 3.2 Traffic-light icon
- R4. The icon reflects overall health: green (all good), yellow (worth a look), red (problem).
- R5. Apple-like style: a monochrome glyph that follows light/dark mode, plus a **small colored dot** as the
  indicator. **[OPEN: variant, see §6]**
- R6. Overall health is the worst of all metrics, with hysteresis so it does not flicker
  (a level must hold for a few seconds before it changes).

### 3.3 Popover
- R7. Clicking the icon opens a native-looking popover (system materials and typography, minimal charts).
- R8. **Problems first:** yellow/red metrics are listed at the top, in their own section.
- R9. **No scrolling:** everything fits in one fixed-size view.
- R10. Default window: last 30 seconds. Range selector: 30 s · 5 min · 1 h. **[ASSUMPTION]**
- R11. Each metric shows its current value prominently plus a small sparkline.

### 3.4 Metrics (v1)

| # | Metric | What is shown |
|---|---|---|
| M1 | **Ping** (primary) | Latency (ms), packet loss (%), jitter, against several targets. **[OPEN: targets]** |
| M2 | CPU | Total usage (%) |
| M3 | Memory | Used / total, plus the system **memory pressure** (used % is misleading because macOS uses spare RAM as cache) |
| M4 | Disk | Free space (GB) plus read/write throughput. **[ASSUMPTION]** |
| M5 | Battery | Power in **watts** (battery discharge, or charger input when plugged in). Charge % is not repeated since macOS already shows it. **[OPEN: confirm]** |
| M6 | Network | Download and upload throughput (Mbps) |
| M7 | Thermal state | Shown only when macOS is throttling. Essentially free to read. The CPU temperature is shown next to CPU usage when the SMC exposes it. |

### 3.5 Candidate extras **[OPEN]**
- E1. Top 3 processes by CPU (computed only while the popover is open).
- E2. Fan speed (Macs with fans only; requires reading the SMC).
- E3. Wi‑Fi network name and signal quality.

## 4. Default traffic-light thresholds **[ASSUMPTION, configurable]**

| Metric | Yellow | Red |
|---|---|---|
| Ping (primary target, last 10 samples) | avg > 80 ms or loss > 2 % | avg > 200 ms, loss > 10 %, or no replies |
| CPU | > 80 % sustained 30 s | > 95 % sustained 60 s |
| Memory | pressure "warning" | pressure "critical" |
| Disk | < 15 % free | < 5 % free |
| Battery | draw > 25 W on battery, sustained 30 s | — |
| Thermal | "serious" | "critical" |

## 5. Out of scope for v1
- Notifications and sounds.
- Data export, history longer than 1 hour, persisting history across restarts.
- Mac App Store distribution (the sandbox complicates unprivileged ICMP and battery reads).
- Complex settings. v1 ships a minimal settings surface (ping targets, launch at login, thresholds).

## 6. Open questions

| # | Question | Default until decided |
|---|---|---|
| Q1 | Which ping targets, and which one is primary? | Router, Cloudflare (primary), Google, AWS São Paulo, AWS N. Virginia |
| Q2 | Battery: power draw (W) or time remaining? | Power draw (W) |
| Q3 | Icon: always show the dot, or only when not green? Show ping ms next to the icon? | Always show the dot; no text |
| Q4 | Which extras (§3.5)? | None beyond thermal state |
| Q5 | Distribution: Apple Developer ID signing and notarization? | Ad-hoc signed builds |
| Q6 | Reference hardware (chip, macOS version) for measuring the budget | — |
