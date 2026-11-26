# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Disk: free space stayed at the value read at launch instead of updating, so it drifted away from
  what System Settings shows. It now also shows one decimal place ("248.6 GB") in the same decimal units
  as macOS.

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

[Unreleased]: https://github.com/Saissaken/dotwell/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Saissaken/dotwell/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Saissaken/dotwell/releases/tag/v0.1.0
