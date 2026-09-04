#!/usr/bin/env bats
#
# Tests for bin/detect-domain.sh and the underlying detect_domain function.

load helpers/common

setup() {
    cd "$REPO_ROOT"
}

@test "detect-domain: mobile path resolves to mobile" {
    run ./bin/detect-domain.sh "/Users/x/workspace/mobile/acme-mobile"
    [ "$status" -eq 0 ]
    [ "$output" = "mobile" ]
}

@test "detect-domain: web-react path resolves to web-react" {
    run ./bin/detect-domain.sh "/Users/x/workspace/web-react/my-app"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}

@test "detect-domain: backend-node path resolves to backend-node" {
    run ./bin/detect-domain.sh "/Users/x/workspace/backend-node/api"
    [ "$status" -eq 0 ]
    [ "$output" = "backend-node" ]
}

@test "detect-domain: data-extraction path resolves to data-extraction" {
    run ./bin/detect-domain.sh "/Users/x/workspace/data-extraction/etl"
    [ "$status" -eq 0 ]
    [ "$output" = "data-extraction" ]
}

@test "detect-domain: unknown path returns non-zero" {
    run ./bin/detect-domain.sh "/Users/x/workspace/something-else/proj"
    [ "$status" -ne 0 ]
}

@test "detect-domain: empty arg returns non-zero with usage" {
    run ./bin/detect-domain.sh
    [ "$status" -ne 0 ]
    assert_contains "$output" "Usage"
}

@test "detect-domain: domain name appears as substring in component" {
    # "acme-mobile" contains "mobile" → mobile
    run ./bin/detect-domain.sh "/some/path/acme-mobile/sub"
    [ "$status" -eq 0 ]
    [ "$output" = "mobile" ]
}

@test "detect-domain: a project under an aliased folder resolves to the domain" {
    # web-react registers workspace/web as an alias, so "web" identifies it.
    run ./bin/detect-domain.sh "/Users/x/workspace/web/my-app"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}

@test "detect-domain: the canonical folder still resolves" {
    run ./bin/detect-domain.sh "/Users/x/workspace/web-react/my-app"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}

@test "detect-domain: a path matching two domains is ambiguous, not a guess" {
    # One component per domain: whichever the detector picked would be wrong
    # half the time, so it must refuse instead.
    run ./bin/detect-domain.sh "/Users/x/workspace/mobile/web-react-port"
    [ "$status" -ne 0 ]
    assert_contains "$output" "ambiguous"
}

@test "detect-domain: two aliases of one domain are not a conflict" {
    # "web" (alias) and "web-react" (domain name) both match; they collapse
    # to the same owner and must resolve, not report ambiguity.
    run ./bin/detect-domain.sh "/Users/x/workspace/web/web-react-app"
    [ "$status" -eq 0 ]
    [ "$output" = "web-react" ]
}
