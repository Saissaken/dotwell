# Contributing

Thanks for your interest in Dotwell! This guide explains how to propose changes.

## Ground rules

1. **Resource usage comes first.** Any change that adds CPU work, memory, wakeups or binary size must justify
   it. If your change touches the sampling path, include before/after numbers from Activity Monitor
   (CPU %, Memory, Energy Impact) in the pull request.
2. **No new third-party dependencies** without prior discussion in an issue. Sparkle (updates) is the only one.
3. **No subprocesses.** Read data from system APIs (Mach, IOKit, `sysctl`), never by launching `ping`, `top`, etc.
4. **Everything in English**: code, comments, docs, commit messages and pull requests.

## Development setup

- macOS 13 or later, Xcode 15 or later.
- `make test` runs unit tests, `make app` builds `build/Dotwell.app`.
- `make format` formats the code with `swift format`; `make lint` checks formatting the same way CI does.

## Code style

- Formatting is enforced by `swift format` using [.swift-format](.swift-format). CI fails on lint errors.
- Keep `MonitorCore` free of UI code so it stays unit-testable.
- Prefer value types and fixed-size buffers on the sampling path; avoid allocations per tick.
- Public APIs in `MonitorCore` get a doc comment.

## Screenshots

`PreviewRenderTests` renders the popover with sample data when `PREVIEW_DIR` is set. CI uploads the images as the
`Previews` artifact on every pull request. To refresh the README images in `docs/images`, run the **Screenshots**
workflow on your branch from the Actions tab. If you change the popover UI, include the new previews in your
pull request.

## Tests

- New logic in `MonitorCore` needs unit tests. Keep math (deltas, thresholds, parsing) in pure functions so it
  can be tested without real hardware.
- Live probe tests must tolerate CI runners (no battery, virtualized hardware).
- Every reading is checked against ground truth in `AccuracyTests`: macOS's own tools (`vm_stat`, `sysctl`,
  `df`, `ping`, `dig`) or a load the test creates (busy threads, a 64 MB write, a 10 MB download, a 256 MB
  allocation). A new metric needs such a test. Where the machine can't provide the reading (no internet, no
  sensors in a VM), the test is skipped, never faked.

## Git workflow

- `main` is always releasable. Never push to it directly; every change lands through a pull request with green CI.
- Work on a short-lived branch named `<type>/<short-description>`, e.g. `feat/popover-redesign` or
  `fix/ping-timeout`.
- One focused change per pull request. Split unrelated work into separate pull requests.

### Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <imperative summary, lower case, no period>

<optional body: what and why, wrapped at 72 columns>
```

Types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `style`, `ci`, `build`, `chore`.
Scopes are optional and usually a module or area: `core`, `ping`, `popover`, `icon`, `ci`.
Mark breaking changes with `!` (e.g. `feat(core)!: ...`) and a `BREAKING CHANGE:` footer.

Examples:

```
feat(ping): add IPv6 targets
fix(core): handle 32-bit tick counter wrap
perf(sampler): skip history copy while popover is closed
```

### Pull requests and merging

- The pull request title must be a Conventional Commit; CI checks it.
- Pull requests are merged with **squash and merge**, so each pull request becomes exactly one commit on `main`
  whose message is the pull request title (with its number). Commits inside a branch can be informal.
- The branch is deleted after merging.
- Fill in the pull request template and update `CHANGELOG.md` under **Unreleased** for user-visible changes.

### Releases

Releases follow [Semantic Versioning](https://semver.org/) and are tagged `vMAJOR.MINOR.PATCH` on `main`.
The changelog's **Unreleased** section becomes the release notes. See [docs/RELEASING.md](docs/RELEASING.md).

## Reporting bugs and requesting features

Use the issue templates. For bugs, include your Mac model, chip, macOS version and steps to reproduce.
For security issues, see [SECURITY.md](SECURITY.md).
