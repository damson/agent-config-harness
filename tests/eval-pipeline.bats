#!/usr/bin/env bats
#
# Tests for the shared eval pipeline (lib/scoring.sh via evals/run-eval.sh)
# and the benchmark report's domain selection.
#
# Nothing here calls the real Claude CLI: a stub `claude` on PATH records its
# arguments and stdin, and returns a canned reply the test controls. The repo
# under eval is a synthesized consumer root, so this checkout is never written.

load helpers/common

setup() {
    CONSUMER=$(mktemp -d)
    mkdir -p "$CONSUMER/config" "$CONSUMER/workspace/acme"
    printf 'acme = workspace/acme : CLAUDE.md\n' > "$CONSUMER/config/domains.conf"
    printf '# Acme\n\n- A rule.\n' > "$CONSUMER/workspace/acme/CLAUDE.md"

    STUB=$(mktemp -d)
    cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
dir="$(dirname "$0")"
printf '%s\n' "$*" > "$dir/args"
cat > "$dir/prompt"
if [ -f "$dir/fail" ]; then
    echo "Invalid API key. Please run /login" >&2
    exit 1
fi
if [ -f "$dir/reply" ]; then
    cat "$dir/reply"
    exit 0
fi
cat <<'JSON'
{"date":"2026-01-01T00:00:00Z","domain":"acme","git_hash":"stub","scores":{"clarity":5,"conciseness":5,"completeness":5,"consistency":5,"actionability":5},"total":25,"percentage":100,"grade":"A","findings":[]}
JSON
EOF
    chmod +x "$STUB/claude"
}

teardown() {
    rm -rf "$CONSUMER" "$STUB"
}

run_eval() {
    run env PATH="$STUB:$PATH" AGENT_CONFIG_ROOT="$CONSUMER" "$@" \
        "$REPO_ROOT/evals/run-eval.sh" acme
}

# Write one compact score record, as run-eval.sh would, into the consumer's
# scores dir. The date field is unique per record so a row surfacing in the
# wrong domain's table is detectable.
make_score() {
    local stem="$1" domain="$2" date="$3"
    mkdir -p "$CONSUMER/benchmarks/scores"
    cat > "$CONSUMER/benchmarks/scores/$stem.json" <<EOF
{"date":"${date}T00:00:00Z","domain":"$domain","git_hash":"x","scores":{"clarity":4,"conciseness":4,"completeness":4,"consistency":4,"actionability":4},"total":20,"percentage":80,"grade":"B"}
EOF
}

@test "eval pipeline: result filename carries the full run timestamp" {
    run_eval
    [ "$status" -eq 0 ]
    run bash -c "ls '$CONSUMER/evals/results/'"
    # Seconds precision, and the -<domain>.json suffix intact (the CI action
    # selects results via `*-<domain>.json`).
    printf '%s' "$output" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}-acme\.json$'
}

@test "eval pipeline: a same-day rerun adds a second result instead of overwriting" {
    run_eval
    [ "$status" -eq 0 ]
    sleep 1
    run_eval
    [ "$status" -eq 0 ]
    run bash -c "ls '$CONSUMER/evals/results/' | wc -l"
    [ "$output" -eq 2 ]
    run bash -c "ls '$CONSUMER/benchmarks/scores/' | wc -l"
    [ "$output" -eq 2 ]
}

@test "eval pipeline: unparsable output is saved as RAW and fails the run" {
    printf 'I cannot score this, sorry.\n' > "$STUB/reply"
    run_eval
    [ "$status" -ne 0 ]
    assert_contains "$output" "Saved raw response"
    run bash -c "ls '$CONSUMER/evals/results/'"
    assert_contains "$output" "-acme-RAW.txt"
    assert_not_contains "$output" "acme.json"
}

@test "eval pipeline: a failing claude call surfaces the CLI's stderr" {
    touch "$STUB/fail"
    run_eval
    [ "$status" -ne 0 ]
    assert_contains "$output" "Invalid API key"
}

@test "eval pipeline: the model is pinned by default" {
    run_eval
    [ "$status" -eq 0 ]
    run cat "$STUB/args"
    assert_contains "$output" "--model claude-sonnet-5"
}

@test "eval pipeline: EVAL_MODEL overrides the pinned model" {
    run_eval EVAL_MODEL=claude-opus-5
    [ "$status" -eq 0 ]
    run cat "$STUB/args"
    assert_contains "$output" "--model claude-opus-5"
}

@test "eval pipeline: scored file content is fenced by scored-content markers" {
    run_eval
    [ "$status" -eq 0 ]
    run cat "$STUB/prompt"
    assert_contains "$output" "<<<BEGIN SCORED CONTENT: workspace/acme/CLAUDE.md>>>"
    assert_contains "$output" "<<<END SCORED CONTENT: workspace/acme/CLAUDE.md>>>"
    # The scored file itself sits between the markers.
    assert_contains "$output" "- A rule."
}

@test "report: a domain never inherits rows from a domain it suffixes" {
    # skill-web's filename stem ends in "-web.json", so a filename glob for the
    # "web" domain would swallow it; web-react guards the other direction.
    make_score "2026-01-01T000000-web"       web       2026-01-01
    make_score "2026-01-01T000000-web-react" web-react 2026-02-02
    make_score "2026-01-01T000000-skill-web" skill-web 2026-03-03
    run env AGENT_CONFIG_ROOT="$CONSUMER" "$REPO_ROOT/benchmarks/report.sh"
    [ "$status" -eq 0 ]
    # Every record's unique date appears exactly once — a duplicate means a
    # row was printed under a second domain's table.
    for d in 2026-01-01 2026-02-02 2026-03-03; do
        [ "$(printf '%s\n' "$output" | grep -c "$d")" -eq 1 ]
    done
}
