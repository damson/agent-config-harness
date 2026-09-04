# Shared test helpers — sourced by every .bats file.
#
# Provides:
#   - REPO_ROOT (absolute)
#   - setup_test_home → isolated $HOME for tests that touch ~/.claude
#   - teardown_test_home → cleanup

# Absolute path to the repo under test.
export REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

# Build an isolated $HOME so we don't pollute the real one.
setup_test_home() {
    TEST_HOME=$(mktemp -d)
    export ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
}

teardown_test_home() {
    [ -n "${ORIG_HOME:-}" ] && export HOME="$ORIG_HOME"
    [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
}

# Build a temporary "fake project" with a given name (used for stealth/sync tests).
make_fake_project() {
    local name="$1"
    local dir
    dir=$(mktemp -d -t "ai-setup-$name-XXXX")
    # rename the leaf to include the domain name so detect_domain matches
    local domain_dir="$dir/$name"
    mkdir -p "$domain_dir"
    ( cd "$domain_dir" && git init -q && git commit --allow-empty -q -m "init" )
    printf '%s' "$domain_dir"
}

# Repo-relative path of every skill directory. Skills live at the top level or
# one level down inside a group container, so search both depths and treat
# "holds a SKILL.md" as the definition. Mirrors list_skill_dirs() in
# lib/common.sh — keep the two in step.
list_skill_paths() {
    find "$REPO_ROOT/user-dev/skills" -mindepth 1 -maxdepth 2 -type d \
        -exec test -f '{}/SKILL.md' \; -print | sort
}

# Assert that a string contains a substring — and actually fail when it does not.
#
# `[[ "$output" == *"x"* ]]` looks like an assertion but is inert unless it is
# the LAST command in the test: bash's errexit does not fire for a failing `[[ ]]`
# in that position, so bats records the test as passing. A failing `grep` is an
# ordinary command failure, which bats does catch wherever it appears.
assert_contains() {
    local haystack="$1" needle="$2"
    if ! printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf 'expected output to contain: %s\n' "$needle" >&2
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf 'expected output NOT to contain: %s\n' "$needle" >&2
        return 1
    fi
}

assert_starts_with() {
    local haystack="$1" prefix="$2"
    case "$haystack" in
        "$prefix"*) return 0 ;;
        *) printf 'expected output to start with: %s\n' "$prefix" >&2; return 1 ;;
    esac
}

assert_not_starts_with() {
    local haystack="$1" prefix="$2"
    case "$haystack" in
        "$prefix"*) printf 'expected output NOT to start with: %s\n' "$prefix" >&2; return 1 ;;
        *) return 0 ;;
    esac
}

# Guard a test that needs python3 + PyYAML to parse a config file.
#
# A skip is the right answer on a contributor's machine and the wrong one in
# CI: there, a skipped test reports "ok" and the check it was written to make
# silently stops happening. So skip locally, fail loudly under CI.
require_python_yaml() {
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
        return 0
    fi
    if [ -n "${CI:-}" ]; then
        printf 'PyYAML is required in CI: this check cannot be allowed to skip\n' >&2
        return 1
    fi
    skip "python3 with PyYAML unavailable"
}
