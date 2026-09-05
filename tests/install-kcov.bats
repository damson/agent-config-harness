#!/usr/bin/env bats
#
# Tests for .github/install-kcov.sh — the coverage job's kcov build step.
#
# Two things are worth holding here, and neither needs a real build:
#
#   1. The Actions cache key describes what was actually built. A key that
#      cannot change when the runner image does will hand a later run a binary
#      linked against libraries that image no longer has.
#   2. A cache hit is verified rather than assumed. The old check reported a
#      hit for any executable file at the path, so a kcov that could not load
#      its libraries printed an empty version and exited 0.
#
# Everything runs against a curated PATH of stubs, so nothing clones, compiles
# or touches apt.

load helpers/common

SCRIPT="$REPO_ROOT/.github/install-kcov.sh"

setup() {
    cd "$REPO_ROOT"
    BIN=$(mktemp -d)
    PREFIX=$(mktemp -d)/kcov      # parent exists, kcov itself does not yet
    local t
    # bash included: `env` resolves the interpreter through this PATH too.
    for t in bash cat cut dirname mktemp printf rm sed uname chmod; do
        ln -s "$(command -v "$t")" "$BIN/$t" 2>/dev/null || true
    done

    # sudo runs its argument list; apt-get records what it was asked for and
    # succeeds. Together these let the rebuild path reach the wrapper for real
    # instead of dying on a missing command.
    printf '#!/bin/sh\nexec "$@"\n' > "$BIN/sudo"
    printf '#!/bin/sh\necho "$@" >> "%s"\nexit 0\n' "$BIN/apt.args" > "$BIN/apt-get"
    # git stops the run at the clone, deliberately: a controlled non-zero exit
    # right after the wrapper, so no test depends on a build happening.
    printf '#!/bin/sh\necho "$@" >> "%s"\nexit 1\n' "$BIN/git.args" > "$BIN/git"
    chmod +x "$BIN/sudo" "$BIN/apt-get" "$BIN/git"
}

teardown() {
    rm -rf "$BIN" "$(dirname "$PREFIX")"
}

# A stub kcov at $PREFIX/bin/kcov. With an argument it prints it and succeeds;
# with none it fails the way a binary missing a shared library does.
stub_cached_kcov() {
    mkdir -p "$PREFIX/bin"
    if [ $# -eq 1 ]; then
        printf '#!/bin/sh\necho "%s"\n' "$1" > "$PREFIX/bin/kcov"
    else
        printf '%s\n' '#!/bin/sh' \
            'echo "kcov: error while loading shared libraries: libdw.so.1" >&2' \
            'exit 127' > "$PREFIX/bin/kcov"
    fi
    chmod +x "$PREFIX/bin/kcov"
}

run_kcov() {
    run env -i PATH="$BIN" HOME="$HOME" KCOV_PREFIX="$PREFIX" \
        bash "$SCRIPT" "$@"
}

# ── The cache key ─────────────────────────────────────────

@test "install-kcov: --cache-key names the version it pins" {
    run_kcov --cache-key
    [ "$status" -eq 0 ]
    assert_contains "$output" "kcov-43-"
}

@test "install-kcov: --cache-key changes when the pinned version changes" {
    run env -i PATH="$BIN" HOME="$HOME" KCOV_PREFIX="$PREFIX" \
        KCOV_VERSION=99 bash "$SCRIPT" --cache-key
    [ "$status" -eq 0 ]
    assert_contains "$output" "kcov-99-"
}

@test "install-kcov: --cache-key carries an image identity, not a hardcoded one" {
    # The regression: the key ended in the literal "noble" written into the
    # workflow. A key that cannot vary with the image is the bug, so assert
    # the script derives a codename field rather than asserting any one value
    # (this suite runs on macOS and on a Linux runner).
    run_kcov --cache-key
    [ "$status" -eq 0 ]
    # kcov-<version>-<uname>-<codename>: four fields, none empty.
    printf '%s' "$output" | grep -qE '^kcov-[^-]+-[^-]+-[^-]+$'
}

@test "install-kcov: --cache-key touches nothing" {
    run_kcov --cache-key
    [ "$status" -eq 0 ]
    [ ! -e "$PREFIX/bin/kcov" ]
}

# ── Cache hits are verified, not assumed ──────────────────

@test "install-kcov: a cached kcov that runs is accepted" {
    stub_cached_kcov "kcov 43"
    run_kcov
    [ "$status" -eq 0 ]
    assert_contains "$output" "cache hit"
    assert_contains "$output" "kcov 43"
}

@test "install-kcov: a cached kcov that cannot run is not reported as a hit" {
    # Regression: the old check was `[ -x ... ]` plus `kcov --version` inside
    # an echo argument, where the failure is discarded. A broken binary was
    # announced as a cache hit and the step exited 0.
    stub_cached_kcov            # no argument: fails like a missing .so
    run_kcov
    # Non-zero because the stub git stops the rebuild at the clone. The point
    # is that it did NOT stop at an exit 0 claiming a usable cache.
    [ "$status" -ne 0 ]
    assert_not_contains "$output" "Already present (cache hit)"
    assert_contains "$output" "will not run, rebuilding"
    # and it does not leave the unusable binary in place for the next step
    [ ! -e "$PREFIX/bin/kcov" ]
}

@test "install-kcov: the build deps go through the bounded apt wrapper" {
    # Regression: a bare `apt-get update && apt-get install` here reintroduced
    # the unbounded wait that .github/install-packages.sh exists to prevent;
    # its header records two 25-minute CI hangs. Assert the options that bound
    # it actually reach apt, rather than that some apt call happened.
    run_kcov
    [ -f "$BIN/apt.args" ]
    run cat "$BIN/apt.args"
    assert_contains "$output" "Acquire::Retries=3"
    assert_contains "$output" "Acquire::http::Timeout=20"
    assert_contains "$output" "libdw-dev"
}

@test "install-kcov: the source is pinned by commit, not by tag alone" {
    # The tarball checksum it replaced could go stale on its own, because
    # GitHub generates /archive tarballs on demand. A commit id cannot, and it
    # still catches a tag moved to different code.
    run_kcov
    [ -f "$BIN/git.args" ]
    run cat "$BIN/git.args"
    assert_contains "$output" "--branch v43"
    grep -q 'a39874f938ce13f7a65f253120d1ec946b349ffe' "$REPO_ROOT/.github/install-kcov.sh"
}
