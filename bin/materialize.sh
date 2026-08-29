#!/usr/bin/env bash
#
# AI Setup — Materialize
#
# Converts a stealth symlink back to a real file temporarily, stages the
# content change in the host repo, then restores the stealth symlink so the
# host repo's working tree remains clean. Domain is auto-detected.
#
# Usage:
#   ./bin/materialize.sh /path/to/project AGENTS.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$SCRIPT_DIR/../lib/common.sh"

if [ $# -lt 2 ]; then
    log_error "Usage: $(basename "$0") <project_path> <file_name>"
fi

PROJECT_PATH="$1"
FILE_NAME="$2"
TARGET_FILE="$PROJECT_PATH/$FILE_NAME"

[ -d "$PROJECT_PATH" ] || log_error "Project path not found: $PROJECT_PATH"

domain=$(detect_domain "$PROJECT_PATH") || log_error "Could not determine domain"
ws=$(get_domain_workspace "$domain")
SOURCE_FILE="$REPO_ROOT/$ws/$FILE_NAME"

[ -f "$SOURCE_FILE" ] || log_error "Source file does not exist: $SOURCE_FILE"

if [ ! -L "$TARGET_FILE" ]; then
    log_error "$TARGET_FILE is not a stealth symlink. Use stealth.sh first, or commit normally."
fi

log_info "Materializing $FILE_NAME (domain=$domain) in $(basename "$PROJECT_PATH")"

SYMLINK_TARGET=$(readlink "$TARGET_FILE")

cd "$PROJECT_PATH"

# 1. Unhide from git
git update-index --no-skip-worktree "$FILE_NAME"

# 2. Replace symlink with content
rm "$FILE_NAME"
cp "$SOURCE_FILE" "$FILE_NAME"

# 3. Stage the content change
git add "$FILE_NAME"
log_ok "Staged content of $SOURCE_FILE in host repo"

# 4. Restore the symlink
rm "$FILE_NAME"
ln -s "$SYMLINK_TARGET" "$FILE_NAME"

# 5. Re-hide from git
git update-index --skip-worktree "$FILE_NAME"

log_ok "Stealth symlink restored. Commit the staged content in the host repo."
