#!/usr/bin/env bash
#
# Install only the packages the runner does not already have, preferring a
# source that does not depend on the Ubuntu mirrors.
#
# The runner image ships jq and shellcheck, so most runs install nothing. bats
# is the exception, and `apt-get` is a bad way to get it: the image points at
# azure.archive.ubuntu.com, which stalls often enough to have hung this repo's
# CI twice for 25+ minutes and then to have blown a 5-minute step timeout while
# apt retried. npm's registry is a different network path and is not affected by
# a broken distro mirror, so anything available there is taken from there, and
# apt is the fallback for the rest.

set -euo pipefail

NPM_PREFIX="${NPM_PREFIX:-$HOME/.local}"

# Package name on npm, where one exists. bats-core publishes `bats`.
npm_name_for() {
    case "$1" in
        bats) echo "bats" ;;
        *)    echo "" ;;
    esac
}

apt_missing=()

for pkg in "$@"; do
    if command -v "$pkg" >/dev/null 2>&1; then
        echo "Already present: $pkg"
        continue
    fi

    npm_pkg=$(npm_name_for "$pkg")
    if [ -n "$npm_pkg" ] && command -v npm >/dev/null 2>&1; then
        # Into a user prefix, not the system one: the runner's node owns
        # /usr/local as root, so a plain `npm install -g` dies with EACCES on
        # its man pages. A user prefix needs no sudo and behaves the same
        # everywhere this script might run.
        echo "Installing $pkg from npm ($npm_pkg) into $NPM_PREFIX"
        npm install -g --prefix "$NPM_PREFIX" "$npm_pkg"
        export PATH="$NPM_PREFIX/bin:$PATH"
        # Later steps are separate shells; this is how a PATH entry survives.
        [ -n "${GITHUB_PATH:-}" ] && echo "$NPM_PREFIX/bin" >> "$GITHUB_PATH"
        continue
    fi

    apt_missing+=("$pkg")
done

[ ${#apt_missing[@]} -eq 0 ] && exit 0

echo "Installing from apt: ${apt_missing[*]}"
export DEBIAN_FRONTEND=noninteractive

# Bound every network wait. Without these a stalled mirror blocks until the
# step's timeout instead of failing.
apt_opts=(-o Acquire::Retries=3
          -o Acquire::http::Timeout=20
          -o Acquire::https::Timeout=20)

sudo apt-get update "${apt_opts[@]}"
sudo apt-get install -y --no-install-recommends "${apt_opts[@]}" "${apt_missing[@]}"
