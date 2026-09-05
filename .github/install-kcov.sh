#!/usr/bin/env bash
#
# Build kcov into ~/.local/kcov. Ubuntu 24.04 (noble) dropped the package, so
# `apt-get install kcov` answers "unable to locate" on current runners. A
# pinned build restored from the Actions cache costs seconds per run.
#
# Usage:
#   .github/install-kcov.sh              build, or accept a cache hit that works
#   .github/install-kcov.sh --cache-key  print the Actions cache key and exit
#
# The cache key lives here, beside the version it pins and the image it is
# built against. Held in the workflow it was a hand-written literal, "noble",
# which stops describing the runner the moment ubuntu-latest rolls forward:
# the key would be unchanged, so a binary built against one libdw would be
# restored onto an image carrying another and die at load.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KCOV_VERSION="${KCOV_VERSION:-43}"
# The commit tag v43 points at. Pinned as a COMMIT rather than as a checksum of
# GitHub's /archive/refs/tags tarball: that tarball is generated on demand and
# is not guaranteed byte-stable, so a regeneration turns every cache-miss run
# red against a constant nobody touched. A commit id is content-addressed, and
# checking it still catches the case the checksum was really there for, a tag
# moved to different code.
KCOV_COMMIT="${KCOV_COMMIT:-a39874f938ce13f7a65f253120d1ec946b349ffe}"
PREFIX="${KCOV_PREFIX:-$HOME/.local/kcov}"

# Only needed when a build is needed. A cache hit that RUNS has its libraries
# by definition, and one that does not run is rebuilt below rather than
# patched up.
BUILD_DEPS=(binutils-dev libdw-dev libelf-dev libcurl4-openssl-dev zlib1g-dev)

image_codename() {
    local codename=unknown
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        codename=$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-unknown}")
    fi
    printf '%s' "$codename"
}

if [ "${1:-}" = "--cache-key" ]; then
    printf 'kcov-%s-%s-%s\n' "$KCOV_VERSION" "$(uname -s)" "$(image_codename)"
    exit 0
fi

# A cache hit is a claim, not a fact. The previous check tested only that the
# file was executable and printed `kcov --version` inside an echo argument,
# where a non-zero exit is discarded: a binary whose libraries had moved
# reported a cache hit, printed an empty version, exited 0, and left the
# coverage step to fail somewhere with no connection to the cause.
if [ -x "$PREFIX/bin/kcov" ]; then
    if version=$("$PREFIX/bin/kcov" --version 2>&1); then
        echo "Already present (cache hit): $version"
        exit 0
    fi
    echo "Cached kcov will not run, rebuilding. It said:"
    printf '%s\n' "$version"
    rm -rf "$PREFIX"
fi

# Through the wrapper rather than a bare apt-get: it bounds every network wait,
# which is what stops a stalled mirror from holding the step open until its
# timeout. Its header records two 25-minute hangs that came from not doing this.
"$SCRIPT_DIR/install-packages.sh" "${BUILD_DEPS[@]}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone --quiet --depth 1 --branch "v${KCOV_VERSION}" \
    https://github.com/SimonKagstrom/kcov.git "$tmp/kcov"
got=$(git -C "$tmp/kcov" rev-parse HEAD)
if [ "$got" != "$KCOV_COMMIT" ]; then
    echo "kcov v${KCOV_VERSION} resolves to $got, expected $KCOV_COMMIT" >&2
    echo "Either the tag moved or the pin is stale. Verify before updating." >&2
    exit 1
fi

cmake -S "$tmp/kcov" -B "$tmp/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
make -C "$tmp/build" -j"$(nproc)" >/dev/null
make -C "$tmp/build" install >/dev/null
"$PREFIX/bin/kcov" --version
