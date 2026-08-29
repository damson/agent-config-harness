#!/usr/bin/env bash
#
# AI Setup — Unstealth
#
# Reverses a stealth symlink: restores the real file content and clears the
# skip-worktree bit so git tracks it normally again. Useful before a tricky
# merge, rebase, or release tag where you want the host repo's file present.
#
# Usage:
#   ./bin/unstealth.sh /path/to/project AGENTS.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

if [ $# -lt 2 ]; then
    log_error "Usage: $(basename "$0") <project_path> <file_name>"
fi

PROJECT_PATH="$1"
FILE_NAME="$2"

[ -d "$PROJECT_PATH" ] || log_error "Project path not found: $PROJECT_PATH"

log_info "Restoring real file: $FILE_NAME in $PROJECT_PATH"

cd "$PROJECT_PATH"

# Clear skip-worktree so git tracks the file again
git update-index --no-skip-worktree "$FILE_NAME" 2>/dev/null || true

# Restore from index (removes the symlink, restores real content)
git checkout "$FILE_NAME"

log_ok "$FILE_NAME restored to its tracked state. Safe to git pull/merge/rebase."
