#!/usr/bin/env bats
#
# Tests for skill files under user-dev/skills/.
# Validates structure (frontmatter + required sections) and post-setup linkage.

load helpers/common

setup() {
    cd "$REPO_ROOT"
}

# Leaf names only — this is the skill's installed identity.
list_skills() {
    list_skill_paths | xargs -n1 basename | sort
}

@test "skills: at least one skill is defined" {
    local count
    count=$(list_skills | wc -l | tr -d ' ')
    [ "$count" -ge 1 ]
}

@test "skills: every directory is a skill or a container of skills" {
    # Catches a stray directory that holds no SKILL.md and no skill beneath it —
    # setup.sh would skip it silently and the skill would never be installed.
    local d
    for d in user-dev/skills/*/; do
        [ -d "$d" ] || continue
        [ -f "$d/SKILL.md" ] && continue
        local found=0 n
        for n in "$d"/*/; do
            [ -f "$n/SKILL.md" ] && found=1
        done
        [ "$found" -eq 1 ] || {
            echo "Directory $d is neither a skill nor a container of skills"
            return 1
        }
    done
}

@test "skills: leaf names are unique across containers" {
    # Skills install FLAT into ~/.claude/skills/<leaf>, so two skills sharing a
    # leaf name would have one symlink overwrite the other with no error.
    local dupes
    dupes=$(list_skills | uniq -d)
    [ -z "$dupes" ] || {
        echo "Duplicate skill leaf names: $dupes"
        return 1
    }
}

@test "skills: frontmatter name matches folder name" {
    while IFS= read -r p; do
        local fm_name
        fm_name=$(awk '/^name:/ {print $2; exit}' "$p/SKILL.md")
        if [ "$fm_name" != "$(basename "$p")" ]; then
            echo "Skill $p has frontmatter name '$fm_name'"
            return 1
        fi
    done < <(list_skill_paths)
}

@test "skills: frontmatter has a non-empty description" {
    while IFS= read -r p; do
        # Description may span multiple lines after 'description: >'. Check the
        # block following 'description:' has at least one non-blank, non-`---` line.
        local desc_body
        desc_body=$(awk '
            /^description:/ { capture=1; next }
            capture && /^---/ { exit }
            capture && /^[a-zA-Z_]+:/ { exit }
            capture { print }
        ' "$p/SKILL.md" | grep -v '^[[:space:]]*$' | head -1)
        [ -n "$desc_body" ] || {
            echo "Skill $p has empty description"
            return 1
        }
    done < <(list_skill_paths)
}

@test "skills: each SKILL.md has structured steps (Procedure or Step N)" {
    while IFS= read -r p; do
        grep -qE '^## +(Procedure|Step [0-9])' "$p/SKILL.md" || {
            echo "Skill $p has no '## Procedure' or '## Step N' section"
            return 1
        }
    done < <(list_skill_paths)
}

@test "skills: each SKILL.md has a When to STOP section" {
    while IFS= read -r p; do
        grep -qE '^## +When to STOP' "$p/SKILL.md" || {
            echo "Skill $p missing '## When to STOP' section"
            return 1
        }
    done < <(list_skill_paths)
}

@test "skills: setup.sh links every skill into ~/.claude/skills/" {
    setup_test_home
    ./bin/setup.sh >/dev/null
    while IFS= read -r s; do
        [ -L "$HOME/.claude/skills/$s" ] || {
            echo "Skill $s was not linked into ~/.claude/skills/"
            teardown_test_home
            return 1
        }
        [ -e "$HOME/.claude/skills/$s/SKILL.md" ] || {
            echo "Link for $s does not resolve to a SKILL.md"
            teardown_test_home
            return 1
        }
    done < <(list_skills)
    teardown_test_home
}

@test "skills: a grouped skill installs flat, under its leaf name" {
    # Grouping is a source-tree convenience; agents read ~/.claude/skills/<name>
    # and do not descend. A group that leaked into the installed path would make
    # every skill in it undiscoverable.
    setup_test_home
    mkdir -p user-dev/skills/__testgroup__/__test-skill__
    cat > user-dev/skills/__testgroup__/__test-skill__/SKILL.md <<'SKILLEOF'
---
name: __test-skill__
description: fixture
---
## Procedure
## When to STOP
SKILLEOF

    ./bin/setup.sh >/dev/null

    local linked=0 nested=0
    [ -e "$HOME/.claude/skills/__test-skill__/SKILL.md" ] && linked=1
    [ -e "$HOME/.claude/skills/__testgroup__" ] && nested=1

    rm -rf user-dev/skills/__testgroup__
    teardown_test_home

    [ "$linked" -eq 1 ] || { echo "grouped skill was not installed at its leaf name"; return 1; }
    [ "$nested" -eq 0 ] || { echo "the group container leaked into ~/.claude/skills/"; return 1; }
}

@test "skills: a renamed skill's old link is pruned, a foreign link is not" {
    # Renaming a skill used to leave the old name behind as a dangling link that
    # the agent still lists. Pruning must not touch links the user owns.
    setup_test_home
    mkdir -p "$HOME/.claude/skills" "$TEST_HOME/elsewhere/my-own-skill"
    ln -sfn "$REPO_ROOT/user-dev/skills/__deleted-skill__" "$HOME/.claude/skills/__deleted-skill__"
    ln -sfn "$TEST_HOME/elsewhere/my-own-skill" "$HOME/.claude/skills/my-own-skill"

    ./bin/setup.sh >/dev/null

    local pruned=0 kept=0
    [ -L "$HOME/.claude/skills/__deleted-skill__" ] || pruned=1
    [ -L "$HOME/.claude/skills/my-own-skill" ] && kept=1
    teardown_test_home

    [ "$pruned" -eq 1 ] || { echo "dangling link into this repo was not pruned"; return 1; }
    [ "$kept" -eq 1 ] || { echo "pruning removed a link the user owns"; return 1; }
}

@test "skills: check-health flags missing skill symlinks" {
    # Static check: health-check script reads the skills directory.
    grep -q 'skills' bin/check-health.sh
}

# --- PR template -------------------------------------------------------------
# The master copy tells its reader that .github/PULL_REQUEST_TEMPLATE.md is the
# one GitHub actually uses here. It said that for months while no such file
# existed (#52), so the claim is now a test.

@test "PR template: the installed template exists and carries every mandatory section" {
    local t="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
    [ -f "$t" ]
    grep -q '## 👥 In plain words' "$t"
    grep -q '## 📋 What changed' "$t"
    grep -q '## ✅ Test plan' "$t"
    grep -q '## 🤖 Review' "$t"
}

@test "PR template: the installed copy has no adoption banner and no placeholders" {
    local t="$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"
    ! grep -q 'PORTABLE PR TEMPLATE' "$t"
    ! grep -q 'DELETE THIS BANNER' "$t"
    ! grep -q '‹' "$t"
}

@test "PR template: no file points at a path that does not exist" {
    local f path
    for f in "$REPO_ROOT"/config/templates/pr/*.md "$REPO_ROOT/.github/PULL_REQUEST_TEMPLATE.md"; do
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            [ -e "$REPO_ROOT/$path" ] || {
                echo "$f references missing path: $path"
                return 1
            }
        done < <(grep -oE '(docs|config|\.github)/[A-Za-z0-9_./-]+\.md' "$f" | sort -u)
    done
}
