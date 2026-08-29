#!/usr/bin/env bats
#
# The harness managing a DIFFERENT repo's config.
#
# Standalone, the engine and the config it manages are one checkout. A consumer
# repo vendors the harness and sets AGENT_CONFIG_ROOT to itself — at which point
# every path the engine resolves has to be checked twice: engine assets (rubrics,
# templates, scripts) must still come from the harness, and everything belonging
# to the managed repo must come from the consumer. Getting that backwards is
# quiet: it reads the harness's own example domains and reports success.

load helpers/common

setup() {
    CONSUMER=$(mktemp -d)
    mkdir -p "$CONSUMER/config" "$CONSUMER/workspace/acme"
    cat > "$CONSUMER/config/domains.conf" <<'EOF'
acme = workspace/acme : CLAUDE.md
EOF
    printf '# Acme\n\n- A rule.\n' > "$CONSUMER/workspace/acme/CLAUDE.md"
}

teardown() { rm -rf "$CONSUMER"; }

@test "consumer mode: REPO_ROOT follows AGENT_CONFIG_ROOT, HARNESS_ROOT does not" {
    run env AGENT_CONFIG_ROOT="$CONSUMER" bash -c ". $REPO_ROOT/lib/common.sh; echo \"\$REPO_ROOT|\$HARNESS_ROOT\""
    [ "$status" -eq 0 ]
    assert_contains "$output" "$CONSUMER|"
    assert_contains "$output" "|$REPO_ROOT"
}

@test "consumer mode: the registry read is the consumer's, not the harness's" {
    run env AGENT_CONFIG_ROOT="$CONSUMER" bash -c ". $REPO_ROOT/lib/common.sh; list_domains | tr '\n' ' '"
    [ "$status" -eq 0 ]
    assert_contains "$output" "acme"
    # The harness ships its own example domains. Seeing one here means the
    # override was ignored and the engine is managing itself.
    assert_not_contains "$output" "web-react"
    assert_not_contains "$output" "mobile"
}

@test "consumer mode: domain files resolve under the consumer" {
    run env AGENT_CONFIG_ROOT="$CONSUMER" bash -c ". $REPO_ROOT/lib/common.sh; get_domain_workspace acme"
    [ "$output" = "workspace/acme" ]
}

@test "consumer mode: unset AGENT_CONFIG_ROOT leaves the harness managing itself" {
    run bash -c ". $REPO_ROOT/lib/common.sh; [ \"\$REPO_ROOT\" = \"\$HARNESS_ROOT\" ] && echo same"
    [ "$output" = "same" ]
}

@test "consumer mode: a bad AGENT_CONFIG_ROOT fails loudly instead of falling back" {
    # Silently falling back to the harness would manage the wrong repo's config.
    run env AGENT_CONFIG_ROOT="/definitely/not/a/directory" bash -c ". $REPO_ROOT/lib/common.sh; echo reached"
    [ "$status" -ne 0 ]
    assert_not_contains "$output" "reached"
}
