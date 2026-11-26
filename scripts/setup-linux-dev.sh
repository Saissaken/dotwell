#!/usr/bin/env bash
# Installs a Linux Swift toolchain so `make lint` / `make format` run outside macOS.
#
# Meant for Linux cloud and CI-like sandboxes (e.g. Claude Code cloud sessions) where
# download.swift.org may be unreachable: the toolchain is taken from the official
# `swift` image on Docker Hub, without needing a Docker daemon.
#
# The app itself can't be built on Linux (AppKit, SwiftUI, IOKit, Darwin), so this only
# makes formatting checks available. Keep SWIFT_VERSION in sync with the Swift version
# that the CI runner reports (`swift --version` step in .github/workflows/ci.yml), so
# swift-format behaves exactly as it does in CI.
#
# Usage: scripts/setup-linux-dev.sh   (idempotent; needs root for /opt and apt)
set -euo pipefail

SWIFT_VERSION="${SWIFT_VERSION:-6.1.2}"
PREFIX="${SWIFT_PREFIX:-/opt/swift}"
IMAGE="library/swift"
TAG="${SWIFT_VERSION}-noble"

if [ "$(uname -s)" != "Linux" ]; then
    echo "setup-linux-dev: not Linux, nothing to do (use Xcode on macOS)." >&2
    exit 0
fi

link_tools() {
    for tool in swift swiftc swift-format; do
        if [ -x "$PREFIX/usr/bin/$tool" ]; then ln -sf "$PREFIX/usr/bin/$tool" "/usr/local/bin/$tool"; fi
    done
}

if "$PREFIX/usr/bin/swift" --version 2>/dev/null | grep -q "swift-${SWIFT_VERSION}-RELEASE"; then
    link_tools
    echo "setup-linux-dev: Swift ${SWIFT_VERSION} already installed in ${PREFIX}."
    exit 0
fi

case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) echo "setup-linux-dev: unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac

# Runtime libraries the toolchain links against (the same set the official image installs).
packages=(binutils libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libncurses-dev libpython3-dev
    libsqlite3-0 libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata zlib1g-dev)
missing=()
for package in "${packages[@]}"; do
    dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "setup-linux-dev: installing ${missing[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
fi

registry="https://registry-1.docker.io/v2/${IMAGE}"
token="$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${IMAGE}:pull" |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["token"])')"
auth=(-H "Authorization: Bearer ${token}")

# Image index -> manifest for this architecture -> the largest layer, which holds the toolchain in /usr.
manifest_digest="$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.oci.image.index.v1+json' \
    "${registry}/manifests/${TAG}" | python3 -I -c '
import json, sys
index = json.load(sys.stdin)
print(next(m["digest"] for m in index["manifests"]
           if m["platform"]["os"] == "linux" and m["platform"]["architecture"] == sys.argv[1]))' "$arch")"
layer="$(curl -fsSL "${auth[@]}" -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
    "${registry}/manifests/${manifest_digest}" | python3 -I -c '
import json, sys
print(max(json.load(sys.stdin)["layers"], key=lambda layer: layer["size"])["digest"])')"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
echo "setup-linux-dev: downloading Swift ${SWIFT_VERSION} (${arch}, ~900 MB)…"
curl -fsSL "${auth[@]}" -o "$work/toolchain.tar.gz" "${registry}/blobs/${layer}"
echo "${layer#sha256:}  $work/toolchain.tar.gz" | sha256sum --check --status

rm -rf "$PREFIX"
mkdir -p "$PREFIX"
tar -xzf "$work/toolchain.tar.gz" -C "$PREFIX" usr
link_tools
swift --version
