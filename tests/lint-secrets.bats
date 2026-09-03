#!/usr/bin/env bats
#
# Tests for bin/lint-secrets.sh — one dirty fixture per pattern (proven to
# fail: each went red with its pattern removed from PATTERNS), a clean repo
# that must stay green, and the exclusions (path-based dirs, log files,
# untracked files).
#
# The scan target is a throwaway git repo passed via AGENT_CONFIG_ROOT, so
# nothing here depends on this repo's own content.

load helpers/common

setup() {
    SCAN_REPO=$(mktemp -d -t ai-setup-lint-XXXX)
    git -C "$SCAN_REPO" init -q
}

teardown() {
    [ -n "${SCAN_REPO:-}" ] && [ -d "$SCAN_REPO" ] && rm -rf "$SCAN_REPO"
}

# plant <relpath> <content> — write a file into the scan repo and track it.
plant() {
    local path="$SCAN_REPO/$1"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$2" > "$path"
    git -C "$SCAN_REPO" add -f "$1"
}

run_lint() {
    run env AGENT_CONFIG_ROOT="$SCAN_REPO" "$REPO_ROOT/bin/lint-secrets.sh"
}

# ── Each pattern fires on a planted value ─────────────────

@test "lint-secrets: api key assignment fires" {
    # NOTE: deliberately lowercase — the pattern is case-sensitive, so an
    # uppercase API_KEY= slips through (docs/architecture.md's own example
    # would not be caught). Flagged in the PR; widening it would flag that
    # very doc, which is out of scope here.
    plant "config.py" 'api_key = "abcd1234efgh5678"'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "Pattern matched"
    assert_contains "$output" "config.py"
}

@test "lint-secrets: password assignment fires" {
    plant "settings.yml" 'password: hunter2hunter2'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "settings.yml"
}

@test "lint-secrets: bearer token fires" {
    plant "notes.md" 'Authorization: Bearer abcdefghij0123456789'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "notes.md"
}

@test "lint-secrets: github token fires" {
    plant "deploy.env" 'GH=ghp_abcdefghij0123456789ABCD'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "deploy.env"
}

@test "lint-secrets: anthropic key fires" {
    plant "llm.env" 'sk-ant-api03-abcdefghij0123456789'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "llm.env"
}

@test "lint-secrets: stripe live key fires" {
    plant "billing.txt" 'sk_live_abcdefghij0123456789'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "billing.txt"
}

@test "lint-secrets: slack webhook fires" {
    plant "hooks.md" 'https://hooks.slack.com/services/T0000000/B0000000/xxxxyyyyzzzz0000'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "hooks.md"
}

@test "lint-secrets: aws access key id fires" {
    plant "creds.txt" 'aws_key AKIAIOSFODNN7EXAMPLE end'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "creds.txt"
}

@test "lint-secrets: private key header fires" {
    plant "key.pem" '-----BEGIN RSA PRIVATE KEY-----'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "key.pem"
}

# ── Clean content stays green ─────────────────────────────

@test "lint-secrets: prose and placeholders do not fire" {
    plant "README.md" 'Set your API key in the console. The token is read
from the environment. Send `Authorization: Bearer <token>`. Test keys look
like sk_test_... and webhooks live under https://hooks.slack.com/services/.
Public keys start with -----BEGIN PUBLIC KEY-----.'
    plant "config.example" 'api_key=$FROM_ENV'
    run_lint
    [ "$status" -eq 0 ]
    assert_contains "$output" "No secret values detected"
}

# ── Exclusions ────────────────────────────────────────────

@test "lint-secrets: evals/results is excluded even as a nested path" {
    # Regression: --exclude-dir='evals/results' took a bare NAME, so the
    # path form never matched and results were scanned anyway.
    plant "evals/results/run-1.json" '"password": "hunter2hunter2"'
    run_lint
    [ "$status" -eq 0 ]
}

@test "lint-secrets: benchmarks/scores is excluded" {
    plant "benchmarks/scores/latest.json" '"api_key": "abcd1234efgh5678"'
    run_lint
    [ "$status" -eq 0 ]
}

@test "lint-secrets: sync/setup logs are excluded at any depth" {
    plant "SYNC_LOG.md" 'password: hunter2hunter2'
    plant "sub/dir/SETUP_LOG.md" 'API_KEY = "abcd1234efgh5678"'
    run_lint
    [ "$status" -eq 0 ]
}

@test "lint-secrets: untracked files are not scanned" {
    # The script's contract is "tracked files": local state (.remember/,
    # logs) must not fail the lint.
    mkdir -p "$SCAN_REPO/.remember"
    printf '%s\n' 'API_KEY = "abcd1234efgh5678"' > "$SCAN_REPO/.remember/scratch.txt"
    run_lint
    [ "$status" -eq 0 ]
}

@test "lint-secrets: tracked secret next to excluded dirs still fires" {
    # Guard against over-broad exclusions: only the registered paths are
    # skipped, not everything under evals/ or benchmarks/.
    plant "evals/run-eval.env" 'token = "abcdefgh12345678"'
    run_lint
    [ "$status" -ne 0 ]
    assert_contains "$output" "run-eval.env"
}
