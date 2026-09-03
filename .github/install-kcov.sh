#!/usr/bin/env bash
#
# Build kcov into ~/.local/kcov — Ubuntu 24.04 (noble) dropped the package, so
# `apt-get install kcov` answers "unable to locate" on current runners. A
# pinned release built once and restored from the Actions cache costs seconds
# per run; the checksum keeps the tarball a build input, not a trust decision.

set -euo pipefail

KCOV_VERSION="${KCOV_VERSION:-43}"
KCOV_SHA256="${KCOV_SHA256:-4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf}"
PREFIX="${KCOV_PREFIX:-$HOME/.local/kcov}"

if [ -x "$PREFIX/bin/kcov" ]; then
    echo "Already present (cache hit): $("$PREFIX/bin/kcov" --version)"
    exit 0
fi

sudo apt-get install -y --no-install-recommends \
    binutils-dev libdw-dev libelf-dev libcurl4-openssl-dev zlib1g-dev

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/kcov.tar.gz" \
    "https://github.com/SimonKagstrom/kcov/archive/refs/tags/v${KCOV_VERSION}.tar.gz"
echo "$KCOV_SHA256  $tmp/kcov.tar.gz" | sha256sum -c -

tar -xzf "$tmp/kcov.tar.gz" -C "$tmp"
cmake -S "$tmp/kcov-$KCOV_VERSION" -B "$tmp/build" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
make -C "$tmp/build" -j"$(nproc)" >/dev/null
make -C "$tmp/build" install >/dev/null
"$PREFIX/bin/kcov" --version
