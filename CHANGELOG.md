# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Settings window (⋯ → Settings…, right-click the menu bar icon, or ⌘,), with changes applied right away:
  - General: open at login, how often to take readings (1, 2, 5 or 10 seconds) and network speed in bits
    or bytes per second.
  - Widgets: show, hide and reorder the popover's cards, and choose which ones show their top app.
  - Ping: pick the internet host (Cloudflare, Google or Quad9), two cloud regions to compare (18 AWS and
    19 Azure regions, or off) and the host that drives the status light.
  - Alerts: turn each alert on or off and set its yellow and red thresholds.
  - Updates: automatic checks and installs, Check Now, and the installed version.
- Hiding the ping card with its alert off stops all pings, and turning off every top-app line stops
  per-app sampling.

### Changed
- Ping now measures a few well-chosen hosts: your router, your internet provider's first router, Cloudflare,
  and two cloud regions (AWS São Paulo and AWS Virginia by default). Google DNS left the defaults, since it
  measures the same thing as Cloudflare, but it can still be picked in Settings.
- "Open at Login" moved from the popover's ⋯ menu to Settings → General.

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

[Unreleased]: https://github.com/Saissaken/dotwell/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Saissaken/dotwell/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Saissaken/dotwell/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Saissaken/dotwell/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Saissaken/dotwell/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Saissaken/dotwell/releases/tag/v0.1.0
