#!/usr/bin/env bash
#
# AI Setup — Stealth
#
# Replaces a tracked file in a host repo with a symlink into ai-setup, then
# marks it skip-worktree so git ignores the swap. Domain is auto-detected
# from the project path so the correct source file is used.
#
# Usage:
#   ./bin/stealth.sh /path/to/project AGENTS.md

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

domain=$(detect_domain "$PROJECT_PATH") || log_error "Could not determine domain"
ws=$(get_domain_workspace "$domain")
SOURCE_FILE="$REPO_ROOT/$ws/$FILE_NAME"

[ -f "$SOURCE_FILE" ] || log_error "Source file does not exist: $SOURCE_FILE"

log_info "Applying stealth: $FILE_NAME (domain=$domain) → $PROJECT_PATH"

cd "$PROJECT_PATH"
ln -sf "$SOURCE_FILE" "$FILE_NAME"
git update-index --skip-worktree "$FILE_NAME" 2>/dev/null || \
    log_warn "skip-worktree failed (is the file tracked by git?)"

log_ok "$FILE_NAME is now a stealth symlink → $SOURCE_FILE"
