# Mac Resource Monitor

[![CI](https://github.com/Saissaken/mac-resource-monitor/actions/workflows/ci.yml/badge.svg)](https://github.com/Saissaken/mac-resource-monitor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey)

A tiny, native macOS menu bar app that tells you at a glance whether your Mac is healthy.
Built for one thing above all: **using as few resources as possible** while it runs all day.

- **Traffic-light status dot** in the menu bar: green, yellow or red, with hysteresis so it never flickers.
- **Ping first**: latency, packet loss and jitter against your router, public DNS and cloud regions.
- **CPU, memory pressure, disk, battery power draw (W) and network throughput** with minimal sparklines.
- **Problems on top**: anything that needs attention is listed first. No scrolling.
- **No dependencies, no helpers, no subprocesses.** Reads everything directly from Mach, IOKit and `sysctl`.

> Status: early development (v0.1). See the [requirements](docs/REQUIREMENTS.md) and
> [technical design](docs/DESIGN.md).

## Resource budget

| | Target (popover closed) |
|---|---|
| CPU | < 0.2 % of one core |
| Memory | < 25 MB |
| Wakeups | < 2 per second |
| App size | < 5 MB |

## Install

Pre-built releases are not published yet. Every CI run attaches a universal, ad-hoc signed
`MacResourceMonitor.zip` artifact. Because it is not notarized, open it the first time with
**right-click → Open**.

## Build from source

Requirements: macOS 13+ and Xcode 15+ (or the matching Swift toolchain).

```sh
git clone https://github.com/Saissaken/mac-resource-monitor.git
cd mac-resource-monitor
make test      # run unit tests
make app       # build build/MacResourceMonitor.app
open build/MacResourceMonitor.app
```

You can also open `Package.swift` in Xcode.

## Project layout

```
Sources/MonitorCore   Probes, ping engine, history and health evaluation (no UI, unit tested)
Sources/MonitorApp    Menu bar item, popover and launch-at-login
Tests/                Unit tests for MonitorCore
scripts/bundle.sh     Assembles and signs the .app bundle
docs/                 Requirements and design
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md) first.

## License

[MIT](LICENSE)
