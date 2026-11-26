# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Cards no longer move when something needs attention: the "Needs Attention" group is gone, and a card that
  has a problem just turns yellow or red where it is.
- Disk and Network are now half-width cards like CPU and Memory, so the popover is shorter. Only Ping still
  spans the full width. A card left alone in the last row keeps its half width.
- The popover is 10% wider (396 pt), so the half-width cards have more room.

### Fixed
- Charts no longer jump sideways while their time range is still filling (for example the first 30 s after
  opening the popover or switching ranges): the line now grows in from the right at its final spacing.
- The icons in the cards' colored circles, and in the route's dots under Ping, are now centered exactly.

## [0.9.0] - 2026-11-26

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
- Ping → Region → Choose… lists every region of AWS, Google Cloud or Azure with how long it takes to reach
  from your Mac right now, fastest first, so you can pick the ones that matter to you. It measures each region
  four times the same way as its row in the popover and shows the best, and only while the window is open. "Change
  Region…" in a region row's right-click menu opens it for that row.
- Settings › Updates › Get nightly builds: follow every change as soon as it's merged, before it's released.
  Official releases stay the default.

### Changed
- Settings is redesigned like System Settings: a sidebar with a search field and colored icons, and one page per
  card with everything about it in one place: whether it shows, its options and its alert. The Alerts tab is
  gone; each alert now lives on its card's page. Drag cards in the sidebar to reorder the popover. Back and
  Forward buttons sit next to the page title, every setting explains itself in a line underneath and in a
  tooltip, and nothing is cut off any more.
- The Thermal card is now part of CPU. It only ever appeared while macOS slowed the Mac down to cool it, which
  was easy to mistake for a missing card. When that happens, the CPU card says "Slowed down to cool" and turns
  yellow or red; CPU → "Warn when macOS slows the Mac down" turns this off. Saved card orders keep working.
- CPU: a "Show temperature and fan speed" switch. Off, Dotwell doesn't read the sensors at all.
- The app CPU scale (whole Mac or one core) moved from General to the CPU page, and the GPU card has a page
  of its own.
- "Top app" is now "Show the busiest app", and "Status light follows" is now "Main host", with what each does.
- Network speed units and the IP addresses switch moved from General to the Network page.
- The website is linked from Settings → General, the About page and the About Dotwell panel.

## [0.8.0] - 2026-11-26

### Added
- GPU card on Macs with Apple silicon, next to CPU: how busy the GPU is, with its chart, the number of GPU
  cores, its temperature, the power it draws and the app using the most of it (WindowServer included). Use
  comes from the GPU driver's own statistics, per-app use from the GPU time macOS keeps for each app (like the
  "% GPU" column of Activity Monitor), power from the same energy counters as `powermetrics`, and temperature
  from the GPU's own sensors; anything your Mac doesn't report is left out instead of guessed. Nothing is
  read while the popover is closed, so its chart starts when you open it. Hide it in Settings › Widgets.

## [0.7.0] - 2026-11-26

### Added
- Top apps: right-click an app, in the line or the list, to copy its process ID or path, show it in Finder,
  quit it, or force quit it (after asking).
- CPU: fan speed next to the temperature ("2,140 rpm", or "fans off" while they're stopped). Hidden on Macs
  without fans, such as the MacBook Air.
- Power: the battery temperature, as the battery itself reports it. Heat is what wears a battery the most.

### Changed
- CPU: the app using the most CPU now shows its share of the whole Mac, on the same scale as the CPU total
  above it (like btop). Before, it used Activity Monitor's scale, where 100% is one core, so an app could
  read 46% while the whole Mac was at 21%. Settings → General can switch back to the per-core scale.

## [0.6.0] - 2026-11-26

### Added
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
- Readings have two intervals in Settings → General: one while the popover is open (0.5, 1 or 2 seconds,
  default 1) and one while it's closed (1, 2, 5, 10 or 30 seconds, default 5). Until now Dotwell measured every
  second all day, even with nothing on screen; the closed popover now wakes the Mac five times less often,
  and the menu bar light still reacts to a problem within about 5 seconds. Charts keep the same time scale
  whatever the interval, and an older slower choice carries over to the closed setting.
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

[Unreleased]: https://github.com/Saissaken/dotwell/compare/v0.9.0...HEAD
[0.9.0]: https://github.com/Saissaken/dotwell/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/Saissaken/dotwell/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/Saissaken/dotwell/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Saissaken/dotwell/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Saissaken/dotwell/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/Saissaken/dotwell/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/Saissaken/dotwell/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Saissaken/dotwell/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Saissaken/dotwell/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/Saissaken/dotwell/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/Saissaken/dotwell/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Saissaken/dotwell/releases/tag/v0.1.0
