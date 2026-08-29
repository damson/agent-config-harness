#!/usr/bin/env bats
#
# Tests for config/external-skills.conf, its lib/common.sh accessors, and
# bin/install-external-skills.sh.
#
# Every test runs against an isolated $HOME and a stubbed PATH, so nothing here
# touches the real ~/.claude or invokes a vendor CLI for real.

load helpers/common

setup() {
    cd "$REPO_ROOT"
    setup_test_home
    STUB_BIN="$TEST_HOME/stub-bin"
    mkdir -p "$STUB_BIN"
    export ORIG_PATH="$PATH"
}

teardown() {
    [ -n "${ORIG_PATH:-}" ] && export PATH="$ORIG_PATH"
    teardown_test_home
}

# Put a fake executable on PATH that records its invocation and creates the
# probe path, standing in for a vendor installer.
stub_installer() {
    local name="$1" creates="$2"
    cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
mkdir -p "$creates"
echo "stub-$name ran: \$*" >>"$TEST_HOME/stub.log"
EOF
    chmod +x "$STUB_BIN/$name"
    export PATH="$STUB_BIN:$ORIG_PATH"
}

# Drop every vendor CLI off PATH — the fresh-machine / CI state. Keeps the
# system utilities the script itself needs (bash, awk, grep) on PATH; a bare
# stub dir would make the script exit 127 and the test would pass for the
# wrong reason.
path_without_vendors() {
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    . "$REPO_ROOT/lib/common.sh"
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if command -v "$(get_external_requires "$id")" >/dev/null 2>&1; then
            skip "vendor CLI for '$id' is in the system PATH on this machine"
        fi
    done < <(list_external_skills)
}

# ── Registry ──────────────────────────────────────────────

@test "registry: config/external-skills.conf exists" {
    [ -f "$REPO_ROOT/config/external-skills.conf" ]
}

@test "registry: every entry has an id and all four :: fields" {
    while IFS= read -r line; do
        case "$line" in \#*|"") continue ;; esac
        id="${line%%=*}"
        id="$(printf '%s' "$id" | tr -d '[:space:]')"
        [ -n "$id" ] || { echo "Entry with empty id: $line"; return 1; }

        rest="${line#*=}"
        # Count '::' separators: four fields means exactly three separators.
        seps=$(printf '%s' "$rest" | grep -o '::' | wc -l | tr -d ' ')
        [ "$seps" -eq 3 ] || {
            echo "Entry '$id' has $seps '::' separators, expected 3: $line"
            return 1
        }
    done < "$REPO_ROOT/config/external-skills.conf"
}

@test "registry: every field of every entry is non-empty" {
    . lib/common.sh
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        for getter in get_external_requires get_external_probe \
                      get_external_install get_external_docs; do
            value=$("$getter" "$id")
            [ -n "$value" ] || { echo "$getter($id) is empty"; return 1; }
        done
    done < <(list_external_skills)
}

# ── Accessors ─────────────────────────────────────────────

@test "list_external_skills: returns every registered provider" {
    . lib/common.sh
    run list_external_skills
    [ "$status" -eq 0 ]
    assert_contains "$output" "android-skills"
    assert_contains "$output" "impeccable"
}

@test "get_external_requires: impeccable → npx" {
    . lib/common.sh
    run get_external_requires "impeccable"
    [ "$output" = "npx" ]
}

@test "get_external_probe: expands a leading ~ to \$HOME" {
    . lib/common.sh
    run get_external_probe "impeccable"
    assert_starts_with "$output" "$HOME/"
    assert_not_starts_with "$output" "~"
}

@test "get_external_install: keeps the full command, flags included" {
    . lib/common.sh
    run get_external_install "impeccable"
    # The '=' and ':' inside the command must survive field splitting.
    assert_contains "$output" "impeccable@latest install"
    assert_contains "$output" "--global"
    assert_contains "$output" "--yes"
}

@test "get_external_docs: returns a URL" {
    . lib/common.sh
    run get_external_docs "android-skills"
    assert_starts_with "$output" "https://"
}

@test "accessors: unknown id returns empty, does not error" {
    . lib/common.sh
    run get_external_install "no-such-provider"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "external_skill_exists: 0 for registered, non-zero for unknown" {
    . lib/common.sh
    run external_skill_exists "impeccable"
    [ "$status" -eq 0 ]
    run external_skill_exists "no-such-provider"
    [ "$status" -ne 0 ]
}

# ── --list ────────────────────────────────────────────────

@test "--list: exits 0 with no TTY and names every provider" {
    run ./bin/install-external-skills.sh --list </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "android-skills"
    assert_contains "$output" "impeccable"
}

@test "--list: reports tool-missing when the vendor CLI is absent" {
    path_without_vendors
    run ./bin/install-external-skills.sh --list </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "not on PATH"
}

@test "--list: reports installed when the probe path exists" {
    . lib/common.sh
    mkdir -p "$(get_external_probe impeccable)"
    run ./bin/install-external-skills.sh --list --only impeccable </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "installed"
}

@test "--list: installs nothing" {
    stub_installer "npx" "$HOME/.claude/skills/impeccable"
    run ./bin/install-external-skills.sh --list --only impeccable </dev/null
    [ "$status" -eq 0 ]
    [ ! -f "$TEST_HOME/stub.log" ]
}

# ── Install ───────────────────────────────────────────────

@test "--yes: installs a missing provider whose CLI is present" {
    . lib/common.sh
    stub_installer "npx" "$(get_external_probe impeccable)"
    run ./bin/install-external-skills.sh --yes --only impeccable </dev/null
    [ "$status" -eq 0 ]
    [ -e "$(get_external_probe impeccable)" ]
    grep -q "stub-npx ran" "$TEST_HOME/stub.log"
}

@test "--yes: is idempotent — a second run does not re-invoke the installer" {
    . lib/common.sh
    stub_installer "npx" "$(get_external_probe impeccable)"
    ./bin/install-external-skills.sh --yes --only impeccable </dev/null
    runs_before=$(wc -l <"$TEST_HOME/stub.log")
    run ./bin/install-external-skills.sh --yes --only impeccable </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "already installed"
    [ "$(wc -l <"$TEST_HOME/stub.log")" -eq "$runs_before" ]
}

@test "--yes: skips a provider whose CLI is absent and still exits 0" {
    path_without_vendors
    run ./bin/install-external-skills.sh --yes </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "skipped"
}

@test "--yes: a failing vendor CLI warns but does not fail the run" {
    . lib/common.sh
    printf '#!/usr/bin/env bash\nexit 3\n' >"$STUB_BIN/npx"
    chmod +x "$STUB_BIN/npx"
    export PATH="$STUB_BIN:$ORIG_PATH"
    run ./bin/install-external-skills.sh --yes --only impeccable </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "failed"
}

@test "no args without a TTY: installs nothing and exits 0" {
    . lib/common.sh
    stub_installer "npx" "$(get_external_probe impeccable)"
    run ./bin/install-external-skills.sh </dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$(get_external_probe impeccable)" ]
    [ ! -f "$TEST_HOME/stub.log" ]
}

@test "no args without a TTY: points at the just recipe when something is missing" {
    stub_installer "npx" "$HOME/.claude/skills/impeccable"
    run ./bin/install-external-skills.sh --only impeccable </dev/null
    [ "$status" -eq 0 ]
    assert_contains "$output" "just skills-install"
}

# ── Arguments ─────────────────────────────────────────────

@test "--only: unknown provider id exits non-zero" {
    run ./bin/install-external-skills.sh --only no-such-provider </dev/null
    [ "$status" -ne 0 ]
    assert_contains "$output" "Unknown provider"
}

@test "unknown flag exits non-zero" {
    run ./bin/install-external-skills.sh --wat </dev/null
    [ "$status" -ne 0 ]
}
