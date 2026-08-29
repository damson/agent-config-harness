#!/bin/bash

# AI Setup - Git Stealth Helper
# This script powers the 'git spull' and 'git scommit' aliases.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION=$1
shift # Remaining args are passed to git commands

# Find all tracked files that are symlinks pointing to the ai-setup repo
get_stealth_files() {
    git ls-files | while read -r file; do
        if [ -L "$file" ]; then
            # Get the real absolute path of the target
            target=$(readlink -f "$file")
            # Handle both absolute and relative targets
            if [[ "$target" == *"$REPO_ROOT"* ]]; then
                echo "$file|$target"
            fi
        fi
    done
}

case "$ACTION" in
    "pull")
        echo "🕵️  Executing Stealth Pull..."
        FILES=$(get_stealth_files)
        
        # 1. Capture state before pull
        declare -A hashes
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            if [ -f "$file" ]; then
                hashes["$file"]=$(shasum -a 256 "$file" | cut -d' ' -f1)
            fi
        done

        # 2. Unstealth
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            git update-index --no-skip-worktree "$file"
            git checkout "$file"
        done

        # 3. Pull
        git pull "$@"

        # 4. Check for remote updates and sync back to ai-setup
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            target=$(echo "$item" | cut -d'|' -f2)
            
            new_hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
            if [ "$new_hash" != "${hashes["$file"]}" ]; then
                echo "🔄 Remote update detected for $file. Syncing back to ai-setup..."
                cp "$file" "$target"
            fi
            
            # 5. Re-stealth
            ln -sf "$target" "$file"
            git update-index --skip-worktree "$file"
        done
        echo "✅ Stealth Pull complete. Environment is synced and hidden."
        ;;

    "commit")
        echo "🚀 Executing Stealth Commit (Review & Branching Mode)..."
        FILES=$(get_stealth_files)

        # 0. Review Step
        echo "--- Changes to be committed ---"
        git status -s
        echo "-------------------------------"
        read -rp "📝 Do you want to sign off on these changes? (y/n) " signoff
        if [[ "$signoff" != "y" ]]; then echo "❌ Aborted."; exit 1; fi

        # 1. Ticket Management
        read -rp "🎫 Enter Jira Ticket Number (or leave empty for the default prefix): " ticket
        if [ -z "$ticket" ]; then
            branch_prefix="TICKET"
        else
            branch_prefix=$(echo "$ticket" | tr '[:lower:]' '[:upper:]')
        fi
        NEW_BRANCH="${branch_prefix}/ai-rules-update-$(date +%Y%m%d-%H%M)"
        
        # 2. Branching
        ORIGINAL_BRANCH=$(git branch --show-current)
        echo "🌿 Creating new branch: $NEW_BRANCH"
        git checkout -b "$NEW_BRANCH"

        # 3. Materialize content
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            target=$(echo "$item" | cut -d'|' -f2)
            git update-index --no-skip-worktree "$file"
            rm "$file"
            cp "$target" "$file"
            git add "$file"
        done

        # 4. Commit
        git commit "$@"

        # 5. Push and Create MR
        echo "📤 Pushing to origin..."
        git push -u origin "$NEW_BRANCH"
        
        if command -v glab &> /dev/null; then
            echo "📝 Creating GitLab Merge Request..."
            glab mr create --fill --yes --remove-source-branch
        else
            echo "⚠️ 'glab' not found. Please create the MR manually."
        fi

        # 6. Cleanup & Return
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            target=$(echo "$item" | cut -d'|' -f2)
            rm "$file"
            ln -s "$target" "$file"
            git update-index --skip-worktree "$file"
        done

        echo "↩️ Returning to $ORIGINAL_BRANCH..."
        git checkout "$ORIGINAL_BRANCH"
        for item in $FILES; do
            file=$(echo "$item" | cut -d'|' -f1)
            target=$(echo "$item" | cut -d'|' -f2)
            ln -sf "$target" "$file"
            git update-index --skip-worktree "$file"
        done

        echo "✅ Stealth Commit complete. MR created and returned to $ORIGINAL_BRANCH."
        ;;

    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac
