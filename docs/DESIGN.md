# Technical design

Status: **draft v0.1** (2026-11-26). Companion to [REQUIREMENTS.md](REQUIREMENTS.md).

> **Decided (2026-11-26):** native Swift, macOS only. The finer choices below (AppKit + SwiftUI, custom charts,
> Swift Package layout, macOS 13+) are proposals open to review.

## 1. Stack

**Swift 5.9+, AppKit for the menu bar item, SwiftUI for the popover content.** The only third-party dependency is
[Sparkle 2](https://sparkle-project.org) for in-app updates; it stays idle between its daily check.

| Option | Typical RAM | Notes |
|---|---|---|
| **Swift + AppKit/SwiftUI** ✅ | 15–25 MB | Direct kernel APIs (Mach, IOKit, sysctl), no extra runtime, native look for free. |
| Pure SwiftUI `MenuBarExtra` | 20–30 MB | Simpler, but less control over the dynamic icon and popover lifecycle. |
| Tauri / Rust | 40–80 MB | WebView means more memory and a non-native look. |
| Electron | 150+ MB | Rejected. |

Details:
- `NSStatusItem` with a template glyph plus a small colored dot. The dot is redrawn **only when the level changes**.
- `NSPopover` hosting SwiftUI. The view tree is **created on open and released on close**, so nothing UI-related
  is retained while the popover is hidden.
- Text never shrinks to fit. `Format` shows every value with at most three significant digits and steps up a
  unit instead of growing (`998 KB/s` → `1.0 MB/s`), digits are tabular, and a test checks that the widest
  caption each module can show fits a half-width module at its fixed size.
- Charts: custom SwiftUI `Canvas` sparklines. Swift Charts is heavier than needed for simple lines.
- Launch at login: `SMAppService.mainApp` (macOS 13+).
- Minimum target: **macOS 13 Ventura**. Universal binary (Apple Silicon + Intel).
- `LSUIElement = YES` (no Dock icon).

## 2. Architecture

```
┌──────────────────── App (single process) ────────────────────┐
│ Sampler (one DispatchSourceTimer with leeway, utility queue)  │
│   ├─ CPUProbe      host_statistics(HOST_CPU_LOAD_INFO)        │
│   ├─ MemoryProbe   host_statistics64 + memorystatus sysctl    │
│   ├─ DiskProbe     URL resource values + IOKit block stats    │
│   ├─ PowerProbe    IOKit AppleSmartBattery                    │
│   ├─ NetworkProbe  sysctl NET_RT_IFLIST2                      │
│   ├─ TemperatureProbe  AppleSMC CPU die sensors               │
│   └─ PingEngine    unprivileged ICMP socket / TCP handshake   │
│          │                                                    │
│          ▼                                                    │
│ TieredSeries (fixed-size Float ring buffers)                  │
│ Thresholds + LevelDebouncer (hysteresis)                      │
│          │  Snapshot (value type, once per tick)              │
│          ▼                                                    │
│ StatusItemController ── PopoverModel/PopoverView (only open)  │
└───────────────────────────────────────────────────────────────┘
```

Modules (Swift Package):
- `MonitorCore`: probes, history, health evaluation. No UI, unit tested.
- `MonitorUI`: popover views and sparklines (SwiftUI).
- `Dotwell` (executable): status item, popover hosting, updates, login item.

## 3. How each metric is read (no root required)

| Metric | API | Cost |
|---|---|---|
| CPU % | `host_statistics(HOST_CPU_LOAD_INFO)`: delta of user+system+nice over total ticks | 1 syscall |
| Memory | `host_statistics64(HOST_VM_INFO64)`: app (internal − purgeable) + wired + compressed. Pressure: `kern.memorystatus_vm_pressure_level` | 2 syscalls |
| Disk space | `volumeAvailableCapacityForImportantUsage` of the boot volume, every 30 s | negligible |
| Disk I/O | IOKit `IOBlockStorageDriver` `Statistics`, delta | 1 IOKit query |
| Battery W | IOKit `AppleSmartBattery`: `Voltage × InstantAmperage`. On AC: `PowerTelemetryData.SystemPowerIn` | 1 IOKit query |
| Network | `sysctl(NET_RT_IFLIST2)` 64-bit counters (`getifaddrs` uses 32-bit counters that wrap at 4 GB). Loopback and point-to-point (VPN) interfaces are excluded to avoid double counting | 1 syscall |
| Thermal state | `ProcessInfo.thermalState`: serious = yellow, critical = red (macOS is throttling) | 1 property read |
| CPU temperature | `AppleSMC` user client: CPU die sensors (`Tp*`/`Te*` floats on Apple silicon, `TC*` sp78 on Intel), found once by listing the SMC keys, averaged, every 5 s **while the popover is open**. No root or entitlements; hidden when no sensor answers (VMs) | 1 IOKit call per sensor |
| Ping | `socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)`, which macOS allows unprivileged. Targets that drop ICMP (e.g. AWS endpoints) use **TCP handshake time on :443** | 1 packet per target |
| Local IP | interface of the default route (`sysctl(NET_RT_FLAGS)` `rtm_index`), its IPv4 from `getifaddrs`, its kind (Wi‑Fi, Ethernet) from `SCNetworkInterfaceCopyAll`. **Only while the popover is open**, again on `NWPathMonitor` path changes | 1 syscall + 1 `getifaddrs` |
| Public IP | `https://1.1.1.1/cdn-cgi/trace` and `https://[2606:4700:4700::1111]/cdn-cgi/trace` (literal addresses force each family, no DNS). Ephemeral `URLSession`, no cache or cookies. Cached until the local address or interface changes, or for 10 min | 2 small HTTPS requests |
| Route (traceroute) | MTR-style: one ICMP echo per TTL (`IP_TTL` on the same unprivileged datagram socket), routers answer "time exceeded" quoting our id and sequence. Reverse DNS per router via `getnameinfo` on a background queue, cached. Hops are grouped into router (hop 1), ISP (private/CGNAT hops up to the first public one, plus later hops in its domain), internet and server; a hop is judged by the best latency and loss at or after it, since routers deprioritize traceroute replies. **Only while the popover is open**, ICMP primary target only | ≤ 30 packets per second, usually ~10 |
| ISP router | the `@isp` ping target: a two-round traceroute to 1.1.1.1 picks the first hop past the gateway with a public or carrier-grade NAT (100.64/10) address. Kept 5 min (1 min when none was found), redone when the gateway changes (checked every 30 s) | ~60 packets per 5 min |
| DNS server | the `@dns` ping target: the first IPv4 `ServerAddresses` entry of `State:/Network/Global/DNS` in the `SCDynamicStore` (what `scutil --dns` lists first), re-read every 30 s. Timed with a real DNS query (A `www.apple.com`, UDP 53, kernel receive timestamp) every 5 s; SERVFAIL, REFUSED or no answer count as lost | 1 `configd` call per 30 s, 1 small UDP packet per 5 s |
| Gateway | default route from `sysctl(NET_RT_FLAGS)`, cached for 30 s | 1 syscall |
| Top app per metric | `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V6)`: deltas of CPU time, disk bytes read+written and `ri_energy_nj`, plus the physical footprint. Per-app network traffic is not available without private APIs (NetworkStatistics) or spawning `nettop`, so the Network module has no top app. Helpers are grouped under their outermost `.app` bundle (`proc_pidpath`, cached per pid and start time); the five largest per resource are kept, each with its main pid (the bundle's own `Contents/MacOS/` executable, else the oldest process) for the click-to-copy list. Only the current user's processes are readable without root, so system daemons are left out. **Only while the popover is open**, every 2 s | 1 syscall per process |

The app never spawns processes (`ping`, `top`, `ioreg`): process creation is by far the most expensive option.

## 4. Sampling cadence

| | CPU/Mem/Net/Disk I/O | ICMP ping | TCP ping | Battery | Disk space |
|---|---|---|---|---|---|
| Popover open | 1 s (0.5–2 s) | every reading | 5 s | 2 s | 30 s |
| Popover closed | 5 s (1–30 s) | every reading | 5 s (or every reading, if slower) | 2 s (or every reading) | 30 s |
| Mac or displays asleep | paused | paused | paused | paused | paused |

The popover has two reading intervals, both set in Settings: while it is open (0.5, 1 or 2 s, default 1 s)
and while it is closed (1, 2, 5, 10 or 30 s, default 5 s). The closed one runs all day, so it is the one that
matters for battery; at 5 s the Mac wakes five times less often than at 1 s, and the menu bar light still
reacts to a problem within one reading. Opening or closing the popover reschedules the timer right away.
Every other column is a duration and keeps it (or runs every reading, if the interval is longer).

History is kept on a clock of half-second slots (`TieredSeries`): a reading fills every slot since the
previous one. CPU, network and disk readings are already averages over that time, and a held ping reply
weighs as much as the time it stands for, so the charts keep one time scale and latency and loss over the
10 s window stay right when the interval changes. Alert hold times are counted in the same slots. A probe
is only reported lost once its 1 s timeout has passed, even when readings come every 0.5 s.
Settings are applied live through `Sampler.apply(_:)` without restarting the timer's history.

Sampling at a fixed interval keeps history continuous; each tick is a handful of syscalls (microseconds).
With the popover closed no history is copied for the UI, nothing is drawn, processes and the CPU temperature
are not sampled (the process probe drops its caches on close), and snapshots only reach the main thread when
the overall level changes (the menu bar dot is all that shows them). If real measurements exceed the
budget, the default closed-popover interval goes up.

- **One timer** with `leeway` so the system can coalesce wakeups.
- All probes run on one serial `.utility` queue and never block a thread waiting for a reply.
- ICMP round trips use the kernel's receive timestamp (`SO_TIMESTAMP_MONOTONIC`), so they measure the network,
  not how long the reply waited for the queue. Ping replies are read once at the start of each tick (no wakeup
  per reply); a probe still unanswered then is lost. A round's probes go out at the end of the tick, so TCP
  handshakes complete while the queue is idle.
- DNS resolution runs off the sampling queue and is cached for 5 minutes.

## 5. History

Each metric keeps a `TieredSeries`:
- 30 s window: last 30 raw samples (buffer of 60).
- 5 min window: 60 averages of 5 samples.
- 1 h window: 120 averages of 30 samples.

That is 240 `Float`s (~1 KB) per series. Lost pings are stored as a negative sentinel, excluded from averages,
and drawn as red ticks. History is in memory only in v1.

## 6. Health

`Thresholds` maps raw values to levels (REQUIREMENTS §4) and `LevelDebouncer` applies hysteresis: raising a level
requires N consecutive samples, lowering requires M. Overall health is the worst level. The popover lists
non-green metrics first.

## 7. Icon

A ~16 pt monochrome template glyph (adapts to light/dark and menu bar highlighting) with a 6 pt dot at the
bottom-right corner using `systemGreen`, `systemYellow` or `systemRed`.
Alternative under discussion (Q3): no dot while green, Apple-style, so color only appears when something needs
attention; optionally the primary ping in ms next to the glyph.

## 8. Build, CI and distribution

- Swift Package plus `scripts/bundle.sh`, which assembles and ad-hoc signs the `.app`. No `.xcodeproj` needed;
  `swift build` and `swift test` work from the command line. The package also opens directly in Xcode.
- GitHub Actions on `macos-15`: format lint, tests, bundle, and the zipped `.app` as a build artifact.
- Releases: pushing a `vX.Y.Z` tag builds a `.dmg` and a `.zip`, signs the zip with Sparkle's EdDSA key and
  publishes a GitHub Release whose `appcast.xml` asset is the update feed. See [RELEASING.md](RELEASING.md).
- Without a Developer ID, builds are ad-hoc signed and must be allowed once in System Settings → Privacy & Security
  (or by removing the quarantine attribute), as described in the README.
  With one, CI can sign and notarize releases; `scripts/bundle.sh` already accepts a `SIGN_IDENTITY`.

## 9. Delivery plan

1. Docs, skeleton, probes, ping, sampler, popover (v0.1).
2. Measure the resource budget on real hardware and tune.
3. Settings: ping targets, primary target, thresholds, cards, interval (v0.4).
4. Decisions from REQUIREMENTS §6 as they land.
5. v1.0 release with signed builds.
