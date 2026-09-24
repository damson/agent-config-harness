#!/usr/bin/env bash
#
# AI Setup — point the pull-request gate at the release that just happened.
#
# The gate scores a pull request with the RELEASED action rather than with the
# pull request's own code, because that job holds an API key and a pull request
# can edit the tree. The cost is a second pin to keep current, and it went four
# releases stale: pull requests were graded by a rubric this repo no longer
# ships, so a check and a local `just eval` on the same file disagreed by
# construction.
#
# Usage:
#   ./bin/bump-gate-pin.sh            # rewrite the pin if the release moved
#   ./bin/bump-gate-pin.sh --dry-run  # say what would change, touch nothing
#
# Env:
#   GATE_WORKFLOW  file holding the pin (default .github/workflows/config-eval.yml)
#   GATE_REF       commit to pin to; default is the latest release's commit
#   GATE_TAG       label for the comment beside it; default is that release's tag
#
# Requires: gh (authenticated) unless both GATE_REF and GATE_TAG are given.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

WORKFLOW="${GATE_WORKFLOW:-$HARNESS_ROOT/.github/workflows/config-eval.yml}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

[ -f "$WORKFLOW" ] || log_error "No such workflow: $WORKFLOW"

# The release the gate should run. Resolved from the tag rather than from
# `target_commitish`, which is a branch name on a release cut from a branch, and
# a branch name is not a pin.
tag="${GATE_TAG:-}"
ref="${GATE_REF:-}"
if [ -z "$tag" ] || [ -z "$ref" ]; then
    require gh "brew install gh"
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
    [ -n "$tag" ] || tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name) \
        || log_error "Could not read the latest release of $repo"
    [ -n "$ref" ] || ref=$(gh api "repos/$repo/commits/$tag" --jq .sha) \
        || log_error "Could not resolve $tag to a commit"
fi

# A short sha, a tag, or an error string must never reach the file: the whole
# point of the pin is that it names one immutable commit of trusted code.
printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' \
    || log_error "Refusing to pin something that is not a full commit sha: $ref"

# `|| true`: grep exits 1 on no match, and under `set -o pipefail` that took
# the script down before it could say what was wrong, which is the failure this
# guard exists to report.
current=$(grep -oE 'agent-config-harness@[0-9a-f]{40}' "$WORKFLOW" | head -1 | cut -d@ -f2 || true)
[ -n "$current" ] || log_error "No pinned commit found in $(basename "$WORKFLOW")"

emit() {
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}
emit current "$current"
emit latest "$ref"
emit tag "$tag"

if [ "$current" = "$ref" ]; then
    log_info "The gate already runs $tag ($current). Nothing to do."
    emit changed false
    exit 0
fi

log_info "Gate pin moves: $current -> $ref ($tag)"
emit changed true
[ "$DRY_RUN" -eq 0 ] || exit 0

# Through a temp file and mv: `sed -i` wants a mandatory empty argument on BSD
# and refuses one on GNU, and this runs on both.
tmp=$(mktemp)
sed -E "s|agent-config-harness@[0-9a-f]{40}( # .*)?|agent-config-harness@$ref # $tag|" \
    "$WORKFLOW" >"$tmp"
mv "$tmp" "$WORKFLOW"

grep -q "agent-config-harness@$ref # $tag" "$WORKFLOW" \
    || log_error "The rewrite did not take; leaving the pin alone was safer"
log_ok "Gate now runs $tag."
