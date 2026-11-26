# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Ping rows: click any row (Router, ISP, DNS, the internet host or a cloud region, or the big number of the main
  host) to see what it measures: the host and the IP address it reaches, how it is timed (ping, opening a
  connection, a small HTTPS request or a DNS query) and how often, and its last minute of readings as average,
  minimum, maximum, loss and jitter, with a small chart. Right-click a row to copy its IP address or host name,
  trace the route to it (the five dots then lead there until you go back or close the popover), change its
  region or host in Settings, or make it the main host the menu bar light follows. It all uses readings Dotwell
  already takes, so it costs nothing while the popover is closed.
- The route under Ping now also shows for an AWS, Azure or Google Cloud main host. These hosts ignore the
  route's ICMP probes, so their dot shows the row's own measurement instead of "No reply".
- Ping: a DNS row for the server your Mac uses to look up names. Every 5 seconds it asks that server a real
  question (the address of www.apple.com, which any resolver has cached) and shows how long the answer takes;
  an error answer or no answer counts as lost. It says "DNS Cloudflare", "DNS Google" and so on for
  well-known resolvers, "DNS Router" when your router answers, or the server's address (hover a row to see the
  address it measures). It follows network changes within 30 seconds.
- Top apps: click the app line in CPU, Memory, Power or Disk to see the five apps using the most of it, each
  with its process ID. Click an app to copy its process ID (for example to `kill` it). An app's process ID is
  its own main process, not one of its helpers; hover an app to see how many processes were added up.
- Charts scroll smoothly: each new reading slides in from the right instead of the line jumping once a second
  (or every 5 or 30 seconds on the longer ranges). This only runs while the popover is open, at up to 30 frames
  per second, and not when Reduce Motion is on.

### Fixed
- Ping: round trips no longer include the time Dotwell itself took to read the reply. With the popover open
  they could read 20–35 ms too high, so the Router row showed 37 ms while the route above it showed 1.3 ms.
  Replies are now timestamped by macOS as they arrive. As a bonus, ICMP replies are read once per tick
  instead of waking the app for each one.
- Ping: AWS and Azure rows (timed with a TCP handshake) now use the round trip measured by macOS itself, so
  they can't include any delay of Dotwell's either.
- The route under Ping now also appears when every widget's top app is turned off.
- CPU temperature on Apple silicon read about 10 °C high on M3 chips (55 °C while btop showed 45 °C). It
  averaged every SMC key starting with `Tp` or `Te`, but on M3 those keys aren't the CPU cores. It now
  averages the sensors macOS itself names after the performance and efficiency core clusters, the same ones
  btop uses, and falls back to the SMC only where they're missing (Intel Macs).

### Changed
- Less work with the popover closed: the main thread is only woken when the menu bar dot changes color,
  instead of every second, and the CPU temperature is only read while the popover is open.

## [0.5.0] - 2026-11-26

### Added
- Network: the Mac's local IP address (with Wi‑Fi, Ethernet or VPN) and its public IPv4 and IPv6. Click an
  address to copy it. The public address is looked up from Cloudflare's 1.1.1.1 only when the popover opens
  on a new network, or after 10 minutes, and nothing runs while the popover is closed. Settings → General can
  hide them (for screen sharing), which also stops the lookup.

## [0.4.1] - 2026-11-26

### Added
- Ping: the ISP row now measures your internet provider's first router. Dotwell finds it with a short
  traceroute (about 60 tiny packets every 5 minutes, and again when you join another network), so you can
  tell whether a slow connection starts at your router or at your provider.

## [0.4.0] - 2026-11-26

### Added
- Settings window (⋯ → Settings…, right-click the menu bar icon, or ⌘,), with changes applied right away:
  - General: open at login, how often to take readings (1, 2, 5 or 10 seconds) and network speed in bits
    or bytes per second.
  - Widgets: show, hide and reorder the popover's cards, and choose which ones show their top app.
  - Ping: pick the internet host (Cloudflare, Google or Quad9), two cloud regions to compare (18 AWS, 23 Google
    Cloud and 19 Azure regions, or off) and the host that drives the status light.
  - Alerts: turn each alert on or off and set its yellow and red thresholds.
  - Updates: automatic checks and installs, Check Now, and the installed version.
- Hiding the ping card with its alert off stops all pings, and turning off every top-app line stops
  per-app sampling.
- Ping: the route to the ping server as five dots (Mac, router, ISP, internet, server), each with the latency up
  to that point and colored by health, plus a one-line verdict such as "Slow from your ISP". Click it to see
  every router on the way. It is traced like MTR, without root or helper tools, and only while the popover is
  open.

### Changed
- Ping now measures a few well-chosen hosts: your router, your internet provider's first router, Cloudflare,
  and two cloud regions (AWS São Paulo and AWS Virginia by default). Google DNS left the defaults, since it
  measures the same thing as Cloudflare, but it can still be picked in Settings. AWS and Azure regions are
  timed with a TCP connection; Google Cloud, whose connections end at the nearest edge, with a small HTTPS
  request answered by the region.
- "Open at Login" moved from the popover's ⋯ menu to Settings → General.
- Text in the modules keeps one fixed size instead of shrinking when a number gets longer. Every value now
  shows at most three significant digits and switches unit instead of growing ("998 KB/s", then "1.0 MB/s";
  "12.3 Mbps"; free disk space as "249 GB"), and digits have a fixed width so values don't jitter. The Disk
  caption is shortened to "R 123 MB/s · W 773 KB/s" so it always fits.

## [0.3.0] - 2026-11-26

### Changed
- The app using the most of each resource now shows inside its module, in one line under the value: CPU,
  Memory, Disk (reads and writes per second) and Battery or Power Adapter (energy in watts). This replaces
  the separate top-processes list, so the popover is shorter. Network has none: macOS only exposes
  per-app traffic through private APIs.

## [0.2.0] - 2026-11-26

### Added
- CPU temperature next to CPU usage, read from the SMC's CPU die sensors (Apple silicon and Intel). It follows
  the temperature unit set in System Settings and is hidden when the Mac doesn't expose the sensors.
- When macOS slows the Mac down to cool it (thermal state "serious" or "critical"), the Thermal module in
  Needs Attention now also shows the CPU temperature.
- Popover: the 3 apps using the most CPU and the most memory, with their icons. Helper processes count
  toward their app (all of Chrome's renderers show up as Chrome). Sampled every 2 s only while the popover
  is open, so it costs nothing the rest of the time.

## [0.1.2] - 2026-11-26

### Fixed
- Disk: free space stayed at the value read at launch instead of updating, so it drifted away from
  what System Settings shows. It now also shows one decimal place ("248.6 GB") in the same decimal units
  as macOS.
- Memory: "used" now matches Activity Monitor's "Memory Used" on Apple Silicon. It was the sum of app,
  wired and compressed memory, which leaves out memory that is not in any page queue (about 1.5 GB on a
  36 GB Mac).

## [0.1.1] - 2026-11-26

### Added
- App icon: a green status dot glowing in a dark well, also used for the disk image volume.
- Once installed, offer to eject the installer disk image and move the downloaded `.dmg` to the Trash.

### Fixed
- Disk image window: the instructions were cut off at the bottom. It now also explains how to allow the
  first launch while the app is not notarized.

## [0.1.0] - 2026-11-26

### Added
- First public release.
- Menu bar item with a traffic-light status dot and launch at login.
- Probes for CPU, memory and memory pressure, disk space and I/O, battery/adapter power, network throughput
  and thermal state.
- Ping engine with unprivileged ICMP and TCP handshake timing, default gateway detection, loss and jitter.
- Sampler with a single coalesced timer, tiered history (30 s / 5 min / 1 h) and health thresholds with
  hysteresis.
- Popover with problems listed first, sparklines and a range selector, styled like Control Center:
  rounded modules, SF Symbols, a native segmented control and an overflow menu.
- README screenshots rendered from the real SwiftUI view in CI (light and dark).
- CI on macOS with tests, format lint and a universal app artifact.
- Automatic updates with Sparkle 2: daily background checks, silent install on quit, and
  **Check for Updates…** in the menu bar icon's right-click menu and the popover's ⋯ menu.
- Release workflow: tagging `vX.Y.Z` publishes a GitHub Release with a `.dmg`, a `.zip` and a signed appcast.
- Disk image with the classic drag-to-Applications window, always at
  `releases/latest/download/Dotwell.dmg`.
- Offer to move the app to the Applications folder when it is opened from anywhere else.
- Homebrew cask: `brew install --cask dotwell` from this repository's tap.

[Unreleased]: https://github.com/Saissaken/dotwell/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/Saissaken/dotwell/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Saissaken/dotwell/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Saissaken/dotwell/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Saissaken/dotwell/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Saissaken/dotwell/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Saissaken/dotwell/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Saissaken/dotwell/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Saissaken/dotwell/releases/tag/v0.1.0
