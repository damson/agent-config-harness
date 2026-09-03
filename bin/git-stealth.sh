#!/usr/bin/env bash
#
# AI Setup — Git Stealth Helper
#
# Powers the 'git spull' and 'git scommit' aliases (installed by setup.sh).
# Operates on tracked files in the host repo that are stealth symlinks into
# this repo (see bin/stealth.sh): it temporarily materializes them so git can
# pull or commit real content, then hides them again behind skip-worktree.
#
# Usage:
#   git-stealth.sh pull   [git-pull args...]
#   git-stealth.sh commit [git-commit args...]
#
# STEALTH_BRANCH_PREFIX names the branch prefix used by 'commit' when no
# ticket reference is entered (default: TICKET).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

require git

if [ $# -lt 1 ]; then
    log_error "Usage: $(basename "$0") <pull|commit> [git args...]"
fi

ACTION=$1
shift # Remaining args are passed to git commands

# sha-256 of a file: shasum on macOS, sha256sum on minimal Linux.
file_hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        sha256sum "$1" | cut -d' ' -f1
    fi
}

# Tracked files that are symlinks into this repo, one "file|target" per line.
# Filenames may contain spaces, so callers must consume this with
# `while IFS='|' read -r file target`, never an unquoted for-loop.
get_stealth_files() {
    git ls-files | while IFS= read -r file; do
        [ -L "$file" ] || continue
        # Real absolute path of the target, whether the link is relative or not.
        target=$(readlink -f "$file" 2>/dev/null) || continue
        case "$target" in
            *"$REPO_ROOT"*) printf '%s|%s\n' "$file" "$target" ;;
        esac
    done
}

# Re-point every stealth file at its target and hide it again.
restealth() {
    while IFS='|' read -r file target; do
        [ -n "$file" ] || continue
        ln -sf "$target" "$file"
        git update-index --skip-worktree "$file"
    done <<<"$FILES"
}

case "$ACTION" in
    pull)
        log_info "Executing Stealth Pull..."
        FILES=$(get_stealth_files)

        # 1. Capture state before pull. Records are "file|hash" lines in a
        #    temp file — stock macOS ships bash 3.2, which has no associative
        #    arrays.
        hash_file=$(mktemp)
        trap 'rm -f "$hash_file"' EXIT
        while IFS='|' read -r file _; do
            [ -n "$file" ] || continue
            if [ -f "$file" ]; then
                printf '%s|%s\n' "$file" "$(file_hash "$file")" >>"$hash_file"
            fi
        done <<<"$FILES"

        # 2. Unstealth
        while IFS='|' read -r file _; do
            [ -n "$file" ] || continue
            git update-index --no-skip-worktree "$file"
            git checkout "$file"
        done <<<"$FILES"

        # 3. Pull
        git pull "$@"

        # 4. Check for remote updates and sync back, then re-stealth
        while IFS='|' read -r file target; do
            [ -n "$file" ] || continue
            old_hash=$(awk -F'|' -v f="$file" '$1 == f { print $2; exit }' "$hash_file")
            new_hash=""
            if [ -f "$file" ]; then
                new_hash=$(file_hash "$file")
            fi
            if [ "$new_hash" != "$old_hash" ]; then
                log_info "Remote update detected for $file — syncing back..."
                cp "$file" "$target"
            fi
            ln -sf "$target" "$file"
            git update-index --skip-worktree "$file"
        done <<<"$FILES"
        log_ok "Stealth Pull complete. Environment is synced and hidden."
        ;;

    commit)
        log_info "Executing Stealth Commit (Review & Branching Mode)..."
        FILES=$(get_stealth_files)

        # 0. Review step
        echo "--- Changes to be committed ---"
        git status -s
        echo "-------------------------------"
        read -rp "Do you want to sign off on these changes? (y/n) " signoff
        if [ "$signoff" != "y" ]; then log_error "Aborted."; fi

        # 1. Ticket management
        read -rp "Enter ticket reference (or leave empty for the default prefix): " ticket
        if [ -z "$ticket" ]; then
            branch_prefix="${STEALTH_BRANCH_PREFIX:-TICKET}"
        else
            branch_prefix=$(printf '%s' "$ticket" | tr '[:lower:]' '[:upper:]')
        fi
        NEW_BRANCH="${branch_prefix}/ai-rules-update-$(date +%Y%m%d-%H%M)"

        # 2. Branching
        ORIGINAL_BRANCH=$(git branch --show-current)
        log_info "Creating new branch: $NEW_BRANCH"
        git checkout -b "$NEW_BRANCH"

        # 3. Materialize content
        while IFS='|' read -r file target; do
            [ -n "$file" ] || continue
            git update-index --no-skip-worktree "$file"
            rm "$file"
            cp "$target" "$file"
            git add "$file"
        done <<<"$FILES"

        # 4. Commit
        git commit "$@"

        # 5. Push and open the MR
        log_info "Pushing to origin..."
        git push -u origin "$NEW_BRANCH"

        if command -v glab >/dev/null 2>&1; then
            log_info "Creating GitLab Merge Request..."
            glab mr create --fill --yes --remove-source-branch
        else
            log_warn "'glab' not found — the branch is pushed; open the MR/PR manually:"
            printf '  branch: %s (pushed with: git push -u origin %s)\n' "$NEW_BRANCH" "$NEW_BRANCH"
            printf '  open a merge/pull request from it into your default branch.\n'
        fi

        # 6. Return & re-stealth. The materialized files are clean (identical
        #    to HEAD), so switch branches FIRST — re-stealthing before the
        #    checkout would count as local changes and make git refuse to
        #    switch — then hide the files again.
        log_info "Returning to $ORIGINAL_BRANCH..."
        git checkout "$ORIGINAL_BRANCH"
        restealth

        log_ok "Stealth Commit complete. Returned to $ORIGINAL_BRANCH."
        ;;

    *)
        log_error "Unknown action: $ACTION"
        ;;
esac
