# Notes for AI agents

Read [CONTRIBUTING.md](CONTRIBUTING.md) first: its rules (resource usage, English only, Conventional Commits,
one focused pull request per change) apply to agents too.

## Before every push

Run `make lint`. If it fails, run `make format`, review the diff and commit it. CI runs the same check with the
same Swift version, so a clean `make lint` means the Lint step will pass.

## Working on Linux (e.g. Claude Code cloud sessions)

- `.claude/hooks/session-start.sh` runs `scripts/setup-linux-dev.sh` at session start, which installs the Linux
  Swift toolchain into `/opt/swift`. If `swift` is missing, run that script yourself.
- Only formatting can be checked on Linux. `swift build` and `swift test` can't work there: every target imports
  macOS-only frameworks (AppKit, SwiftUI, IOKit, Darwin). Compile errors and test failures still show up only in
  CI on macOS, so read code changes carefully before pushing and check the CI result after.
- When CI's `swift --version` changes (runner image updates), bump `SWIFT_VERSION` in
  `scripts/setup-linux-dev.sh` so swift-format keeps behaving the same in both places.
