#!/usr/bin/env bash
#
# AI Setup — install the Claude CLI at the pinned version, for action.yml.
#
# Standalone on purpose, like the other Action entry point (bin/eval-action.sh):
# this runs first, inside somebody else's repository, where lib/common.sh would
# resolve REPO_ROOT against a tree that has no domain registry, and where
# ::error:: / ::notice:: annotations are what surfaces in the run UI rather than
# the shared library's terminal logging. Registered as such in
# docs/architecture.md; do not "fix" it by sourcing lib/common.sh.
#
# Usage:
#   CLAUDE_VERSION=2.1.259 ./bin/install-claude-cli.sh
#
# A runner that already carries a `claude` is used only when its version is the
# one requested. Anything else is installed over, because the action hands
# ANTHROPIC_API_KEY to whatever it ends up running, and SECURITY.md promises the
# CLI is pinned. The one outcome this must never produce is a different version
# than requested, silently.

set -euo pipefail

command -v jq >/dev/null || { echo "::error::jq is required"; exit 1; }

version="${CLAUDE_VERSION:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "::error::claude-version must be an exact x.y.z version"; exit 1; }

# `claude --version` prints something like "2.1.259 (Claude Code)". Take the
# first x.y.z it holds, and treat an unreadable answer as "not the pin".
installed=""
if command -v claude >/dev/null; then
    installed=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
fi

if [ "$installed" = "$version" ]; then
    echo "::notice::Using the pre-installed Claude CLI $installed (matches the requested pin)"
    exit 0
fi

if [ -n "$installed" ]; then
    echo "::notice::Pre-installed Claude CLI is $installed, not the requested $version; installing the pin"
elif command -v claude >/dev/null; then
    echo "::notice::Pre-installed Claude CLI reports no readable version; installing the requested $version"
fi

npm install -g "@anthropic-ai/claude-code@${version}"

# Prove the install produced what was asked for: npm can succeed while an
# earlier copy still wins on PATH, which would put us back where we started.
hash -r 2>/dev/null || true
final=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true
if [ "$final" != "$version" ]; then
    echo "::error::Claude CLI is ${final:-unreadable} after installing $version; refusing to score with an unpinned CLI"
    exit 1
fi
echo "::notice::Claude CLI $final installed"
