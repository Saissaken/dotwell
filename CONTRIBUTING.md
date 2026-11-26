# Contributing

Thanks for your interest in Mac Resource Monitor! This guide explains how to propose changes.

## Ground rules

1. **Resource usage comes first.** Any change that adds CPU work, memory, wakeups or binary size must justify
   it. If your change touches the sampling path, include before/after numbers from Activity Monitor
   (CPU %, Memory, Energy Impact) in the pull request.
2. **No third-party dependencies** without prior discussion in an issue.
3. **No subprocesses.** Read data from system APIs (Mach, IOKit, `sysctl`), never by launching `ping`, `top`, etc.
4. **Everything in English**: code, comments, docs, commit messages and pull requests.

## Development setup

- macOS 13 or later, Xcode 15 or later.
- `make test` runs unit tests, `make app` builds `build/MacResourceMonitor.app`.
- `make format` formats the code with `swift format`; `make lint` checks formatting the same way CI does.

## Code style

- Formatting is enforced by `swift format` using [.swift-format](.swift-format). CI fails on lint errors.
- Keep `MonitorCore` free of UI code so it stays unit-testable.
- Prefer value types and fixed-size buffers on the sampling path; avoid allocations per tick.
- Public APIs in `MonitorCore` get a doc comment.

## Tests

- New logic in `MonitorCore` needs unit tests. Keep math (deltas, thresholds, parsing) in pure functions so it
  can be tested without real hardware.
- Live probe tests must tolerate CI runners (no battery, virtualized hardware).

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`,
  `test:`, `ci:`, `chore:`, with an optional scope, e.g. `feat(ping): add IPv6 targets`.
- Keep pull requests small and focused. Fill in the pull request template.
- Update `CHANGELOG.md` under **Unreleased** for user-visible changes.

## Reporting bugs and requesting features

Use the issue templates. For bugs, include your Mac model, chip, macOS version and steps to reproduce.
For security issues, see [SECURITY.md](SECURITY.md).
