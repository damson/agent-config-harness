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
#   GATE_FOR_COMMIT
#                  resolve the target from the release tagging THIS commit
#                  rather than from whichever release is newest. The push to
#                  main passes the promoted commit, because "latest" there is
#                  the release BEFORE the one being promoted: comparing against
#                  it reported the pin as current while it was a release behind,
#                  so the trigger could never bump anything.
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

# Defined before the resolution below, which has one clean exit of its own.
emit() {
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

# `|| true`: grep exits 1 on no match, and under `set -o pipefail` that took
# the script down before it could say what was wrong, which is the failure this
# guard exists to report.
current=$(grep -oE 'agent-config-harness@[0-9a-f]{40}' "$WORKFLOW" | head -1 | cut -d@ -f2 || true)
[ -n "$current" ] || log_error "No pinned commit found in $(basename "$WORKFLOW")"


# The release the gate should run. Resolved from the tag rather than from
# `target_commitish`, which is a branch name on a release cut from a branch, and
# a branch name is not a pin.
tag="${GATE_TAG:-}"
ref="${GATE_REF:-}"
if [ -z "$tag" ] || [ -z "$ref" ]; then
    require gh "brew install gh"
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

    # Asked for the release that tags one specific commit, answer about that
    # commit or about nothing. A promotion reaches main before anybody tags it,
    # so "no tag yet" is the common answer, and it is a different state from
    # "the pin is already current": the pin is a release behind and the bump is
    # not due yet. Reporting them as the same thing is what made this trigger
    # a no-op on every release it was supposed to act on.
    if [ -n "${GATE_FOR_COMMIT:-}" ] && [ -z "$tag" ]; then
        # The call and the answer are separated on purpose. Folding them
        # together (`... | head -1) || tag=""`) makes a 403, a timeout or a 500
        # arrive as "nothing tags this commit", which is the benign state, so a
        # dead credential would read as a release not tagged yet and the pin
        # would sit stale while every run reported success. That is the exact
        # failure this whole change exists to remove, one level up.
        if ! matching=$(gh api "repos/$repo/tags" --paginate \
                          --jq ".[] | select(.commit.sha == \"$GATE_FOR_COMMIT\") | .name"); then
            log_error "Could not list the tags of $repo, so whether $GATE_FOR_COMMIT is released is unknown. Not reporting that as 'no release yet'."
        fi
        tag=$(printf '%s\n' "$matching" | head -1)
        if [ -z "$tag" ]; then
            log_info "Nothing tags $GATE_FOR_COMMIT yet, so there is no release to pin to. The bump happens when the release is published."
            emit current "$current"
            emit latest ""
            emit tag ""
            emit changed false
            exit 0
        fi
    fi

    [ -n "$tag" ] || tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name) \
        || log_error "Could not read the latest release of $repo"
    [ -n "$ref" ] || ref=$(gh api "repos/$repo/commits/$tag" --jq .sha) \
        || log_error "Could not resolve $tag to a commit"
fi

# A short sha, a tag, or an error string must never reach the file: the whole
# point of the pin is that it names one immutable commit of trusted code.
printf '%s' "$ref" | grep -qE '^[0-9a-f]{40}$' \
    || log_error "Refusing to pin something that is not a full commit sha: $ref"

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
