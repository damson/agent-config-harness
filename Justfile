# AI Setup — personal AI configuration pipeline
#
# Run `just` or `just --list` to see all recipes.
# Install: `brew install just`

# Default recipe: show all available commands.
default:
    @just --list --unsorted

# ── Core ──────────────────────────────────────────────────

# Link configs and skills globally; install git aliases and pre-push hook.
setup:
    @./bin/setup.sh

# Health-check every registered domain and global symlink.
check:
    @./bin/check-health.sh

# Install the impeccable design hook into frontend projects (prompts per project).
impeccable-hooks *ARGS:
    @./bin/impeccable-hooks.sh {{ARGS}}

# Install the third-party skill bundles in config/external-skills.conf (prompts).
skills-install *ARGS:
    @./bin/install-external-skills.sh {{ARGS}}

# Report which external skill providers are installed. Installs nothing.
skills-status:
    @./bin/install-external-skills.sh --list

# ── Skill marketplaces ────────────────────────────────────

# What skill marketplaces are registered, and which of their plugins are installed.
marketplaces-status:
    @./bin/marketplaces.sh status

# Add every registered marketplace and install its plugins. Needs the claude CLI.
marketplaces-install id="":
    @./bin/marketplaces.sh install {{id}}

# Structural check on a skills tree: this repo's by default, or a marketplace's.
validate-skills dir="":
    @./bin/validate-skills.sh {{dir}}

# Structural check on the skills a marketplace installed.
validate-marketplace id:
    @./bin/validate-skills.sh --marketplace {{id}}

# Score a marketplace's skills on the skill rubric. Pass a plugin to narrow it.
eval-marketplace id plugin="":
    @./bin/marketplaces.sh eval {{id}} {{plugin}}

# Scan the repo for secrets / API keys.
lint:
    @./bin/lint-secrets.sh

# Run the full bats test suite.
test:
    @bats tests/

# ── Sync ──────────────────────────────────────────────────

# Sync config improvements from an active project → branch → PR.
sync project:
    @./bin/sync-back.sh "{{project}}"

# Open (or refresh) the release PR promoting develop → main. Never merges.
release:
    @./bin/open-release-pr.sh

# Print the release PR body without touching GitHub.
release-preview:
    @./bin/open-release-pr.sh --dry-run

# Open (or refresh) the PR bringing main back into develop after a release. Never merges.
backmerge:
    @./bin/backmerge.sh

# Say what the back-merge would do, without pushing or opening anything.
backmerge-preview:
    @./bin/backmerge.sh --dry-run

# ── Evaluation ────────────────────────────────────────────

# AI-powered config-quality scoring. Pass a domain or omit for all. Requires Claude CLI.
eval domain="all":
    @./evals/run-eval.sh "{{domain}}"

# AI-powered skill-quality scoring. Pass a skill name or omit for all. Requires Claude CLI.
eval-skills skill="all":
    @./evals/run-skill-eval.sh "{{skill}}"

# Print benchmark score trend per domain.
benchmark:
    @./benchmarks/report.sh

# Snapshot current benchmark scores into git (force-add: scores are gitignored by default).
benchmark-commit:
    @git add -f benchmarks/scores/ && git commit -m "benchmark: snapshot scores $(date +%Y-%m-%d)"

# ── Stealth / Materialize ─────────────────────────────────

# Replace a tracked file in a host repo with a stealth symlink into ai-setup.
stealth project file:
    @./bin/stealth.sh "{{project}}" "{{file}}"

# Restore the real file in a host repo (before a tricky merge/rebase).
unstealth project file:
    @./bin/unstealth.sh "{{project}}" "{{file}}"

# Stage stealth-symlinked content into the host repo as real file content.
materialize project file:
    @./bin/materialize.sh "{{project}}" "{{file}}"
