#!/usr/bin/env bash
#
# AI Setup — Claude Code statusline (prompt line).
#
# Reads the session JSON that Claude Code pipes on stdin and prints two rich
# lines of progress bars and live session telemetry — metrics first, location
# second — with segments joined by " | ":
#
#   ctx ▕████░░░▏ 52% 104k/200k | $0.42 | api $0.40 | +156/-23 | 5h ▕██░░▏ 28% ↺ 2h11m | Opus 4.8 (1M)·high
#   <dir> ⎇ <branch>*
#
#   • ctx        — context-window progress bar, % used, tokens used / window size
#   • $          — estimated session cost (USD)
#   • api $      — org month-to-date API spend (Anthropic Admin cost report, cached ~15m)
#   • +/-        — size: lines added / removed this session
#   • 5h         — usage progress bar for the 5-hour rate window + reset countdown
#   • model      — display name · reasoning effort (or ⚡ fast)
#   • location   — (line 2) dir basename + git branch (+ '*' when the tree is dirty)
#
# The `api $` segment is optional and self-hides unless an Anthropic Admin key is
# provided via $ANTHROPIC_ADMIN_KEY or ~/.claude/anthropic_admin_key (chmod 600).
# It reads a cache file the statusline refreshes in a detached background fetch
# (~15m cadence); the render itself never blocks on the network.
#
# Fields come from the documented statusLine stdin schema (context_window, cost,
# rate_limits, …). Every field is optional — segments self-hide when absent.
#
# Wired via ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" }
# Linked into place by bin/setup.sh, so it restores on every machine.

set -euo pipefail

input="$(cat)"

# ── colours ───────────────────────────────────────────────
c_dir=$'\033[34m'; c_git=$'\033[32m'; c_dirty=$'\033[33m'
c_cost=$'\033[36m'; c_add=$'\033[32m'; c_del=$'\033[31m'
c_model=$'\033[35m'; c_label=$'\033[90m'
c_reset=$'\033[0m'
c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_hot=$'\033[31m'

# ── pull every field in one jq pass ───────────────────────
# Fields are joined with US (\037, a non-whitespace separator) so that EMPTY
# fields survive `read` — a whitespace IFS (tab/space) collapses them and
# shifts every downstream column.
if command -v jq >/dev/null 2>&1; then
    IFS=$'\037' read -r dir model style ctx_pct ctx_used ctx_size \
        cost adds dels fh_pct fh_reset effort fast <<EOF
$(printf '%s' "$input" | jq -r '[
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // .model.id // ""),
  (.output_style.name // ""),
  (.context_window.used_percentage // ""),
  (.context_window.total_input_tokens // ""),
  (.context_window.context_window_size // ""),
  (.cost.total_cost_usd // ""),
  (.cost.total_lines_added // ""),
  (.cost.total_lines_removed // ""),
  (.rate_limits.five_hour.used_percentage // ""),
  (.rate_limits.five_hour.resets_at // ""),
  (.effort.level // ""),
  (.fast_mode // "")
] | map(tostring) | join("")')
EOF
else
    dir="$PWD"; model=""; style=""; ctx_pct=""; ctx_used=""; ctx_size=""
    cost=""; adds=""; dels=""; fh_pct=""; fh_reset=""
    effort=""; fast=""
fi
[ -n "${dir:-}" ] || dir="$PWD"
# "Opus 4.8 (1M context)" → "Opus 4.8 (1M)"
model="${model// context/}"

# ── helpers ───────────────────────────────────────────────

# colour by load: <60 green, <85 yellow, else red
load_colour() { local p=$1; if [ "$p" -lt 60 ]; then printf '%s' "$c_ok"
    elif [ "$p" -lt 85 ]; then printf '%s' "$c_warn"; else printf '%s' "$c_hot"; fi; }

# bar <pct> <width> → coloured ▕████░░░▏
bar() {
    local pct=$1 width=$2 fill i out="" col
    pct=$(printf '%.0f' "$pct" 2>/dev/null || echo 0)
    [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
    fill=$(( (pct * width + 50) / 100 ))
    col="$(load_colour "$pct")"
    for ((i=0; i<width; i++)); do
        if [ "$i" -lt "$fill" ]; then out+="█"; else out+="░"; fi
    done
    printf '%s▕%s▏%s' "$c_label" "${col}${out}${c_label}" "$c_reset"
}

# compact token count: 1234→1k, 1234567→1.2M
fmt_k() {
    local n=$1
    [ -n "$n" ] && [ "$n" -eq "$n" ] 2>/dev/null || { printf '?'; return; }
    if   [ "$n" -ge 1000000 ]; then printf '%d.%dM' "$(( n / 1000000 ))" "$(( (n % 1000000) / 100000 ))"
    elif [ "$n" -ge 1000 ];    then printf '%dk' "$(( n / 1000 ))"
    else printf '%d' "$n"; fi
}

# unix epoch → countdown "2h11m" / "44m" / "now"
fmt_reset() {
    local when=$1 now rem
    [ -n "$when" ] && [ "$when" -eq "$when" ] 2>/dev/null || { printf ''; return; }
    now=$(date +%s); rem=$(( when - now ))
    [ "$rem" -le 0 ] && { printf 'now'; return; }
    if   [ "$rem" -lt 3600 ]; then printf '%dm' "$(( rem / 60 ))"
    else printf '%dh%02dm' "$(( rem / 3600 ))" "$(( (rem % 3600) / 60 ))"; fi
}

# ── api cost (org month-to-date, Admin cost report) ───────
# Renders read only the cache file; the network call happens in a detached
# background fetch, rate-limited to one attempt per ~15 min via a stamp file
# and serialised by a noclobber lock. The whole feature stays dormant unless an
# Admin key is configured.
api_cost_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
api_cost_cache="$api_cost_dir/api-cost-mtd"   # last good value (USD, "0.40")
api_cost_stamp="$api_cost_dir/api-cost.stamp" # last attempt time (cadence)
api_cost_lock="$api_cost_dir/api-cost.lock"   # in-flight guard
api_cost_keyfile="$HOME/.claude/anthropic_admin_key"
api_cost_ttl=15                               # minutes between fetch attempts

# background: fetch month-to-date cost, write dollars to cache on success only.
# Cleanup is an explicit final statement, not an EXIT trap — a trap fires
# unreliably in a background subshell that is reparented when the render exits,
# whereas this function always runs to completion, so the lock is always freed.
_fetch_api_cost() {
    : > "$api_cost_stamp" 2>/dev/null   # stamp the attempt (success or not)
    local key="${ANTHROPIC_ADMIN_KEY:-}" start end resp dollars
    [ -z "$key" ] && [ -f "$api_cost_keyfile" ] && key="$(cat "$api_cost_keyfile" 2>/dev/null)"
    if [ -n "$key" ] && command -v curl >/dev/null 2>&1; then
        start="$(date -u +%Y-%m-01T00:00:00Z)"
        end="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        resp="$(curl -s --max-time 20 -G "https://api.anthropic.com/v1/organizations/cost_report" \
            --data-urlencode "starting_at=$start" \
            --data-urlencode "ending_at=$end" \
            --data-urlencode "bucket_width=1d" \
            --data-urlencode "limit=31" \
            -H "anthropic-version: 2023-06-01" \
            -H "x-api-key: $key" 2>/dev/null)"
        # amount is a decimal string in cents → sum all buckets/results, /100 for USD
        dollars="$(printf '%s' "$resp" | jq -r '
            [ .data[]?.results[]?.amount | select(. != null) | tonumber ] | add // empty | . / 100
        ' 2>/dev/null)"
        case "$dollars" in
            ''|*[!0-9.]*) : ;;   # no data / error / non-numeric → keep last good value
            *) printf '%.2f\n' "$dollars" > "$api_cost_cache.tmp" 2>/dev/null \
                   && mv -f "$api_cost_cache.tmp" "$api_cost_cache" 2>/dev/null ;;
        esac
    fi
    rm -f "$api_cost_lock" 2>/dev/null   # always freed; render only spawns one at a time
}

# foreground: cheap staleness check, then spawn a detached fetch if due
maybe_refresh_api_cost() {
    [ -n "${ANTHROPIC_ADMIN_KEY:-}" ] || [ -f "$api_cost_keyfile" ] || return 0
    mkdir -p "$api_cost_dir" 2>/dev/null || return 0
    # fresh enough? (stamp younger than the TTL)
    if [ -f "$api_cost_stamp" ] && [ -z "$(find "$api_cost_stamp" -mmin +"$api_cost_ttl" 2>/dev/null)" ]; then
        return 0
    fi
    # reap a stale lock left by a killed fetch (>5 min old)
    if [ -f "$api_cost_lock" ] && [ -n "$(find "$api_cost_lock" -mmin +5 2>/dev/null)" ]; then
        rm -f "$api_cost_lock" 2>/dev/null
    fi
    # acquire the lock atomically, then detach the fetch from this render
    if ( set -o noclobber; : > "$api_cost_lock" ) 2>/dev/null; then
        ( _fetch_api_cost >/dev/null 2>&1 </dev/null & ) >/dev/null 2>&1
    fi
}

# ── assemble segments ─────────────────────────────────────
seg=()

# location + git
loc="${c_dir}$(basename "$dir")${c_reset}"
if branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null \
        || git -C "$dir" rev-parse --short HEAD 2>/dev/null)"; then
    dirty=""; git -C "$dir" diff --quiet --ignore-submodules HEAD 2>/dev/null || dirty="${c_dirty}*${c_reset}"
    loc="${loc}  ${c_git}⎇ ${branch}${c_reset}${dirty}"
fi
# (loc is emitted on its own second line, not pushed into seg)

# context window bar
if [ -n "$ctx_pct" ]; then
    p=$(printf '%.0f' "$ctx_pct"); col="$(load_colour "$p")"
    ctx="${c_label}ctx${c_reset} $(bar "$ctx_pct" 8) ${col}${p}%${c_reset}"
    [ -n "$ctx_used" ] && [ -n "$ctx_size" ] && ctx="${ctx} ${c_label}$(fmt_k "$ctx_used")/$(fmt_k "$ctx_size")${c_reset}"
    seg+=("$ctx")
fi

# cost
if [ -n "$cost" ]; then
    costfmt="$(printf '%.2f' "$cost" 2>/dev/null || printf '%s' "$cost")"
    seg+=("${c_cost}\$${costfmt}${c_reset}")
fi

# api cost — org month-to-date spend from the Admin cost report (cached)
maybe_refresh_api_cost
if [ -f "$api_cost_cache" ]; then
    apicost="$(cat "$api_cost_cache" 2>/dev/null)"
    case "$apicost" in ''|*[!0-9.]*) apicost="";; esac
    [ -n "$apicost" ] && seg+=("${c_label}api ${c_reset}${c_cost}\$${apicost}${c_reset}")
fi

# size — lines added / removed
if [ -n "$adds" ] || [ -n "$dels" ]; then
    seg+=("${c_add}+${adds:-0}${c_reset}${c_label}/${c_reset}${c_del}-${dels:-0}${c_reset}")
fi

# 5-hour usage window bar + reset countdown
if [ -n "$fh_pct" ]; then
    p=$(printf '%.0f' "$fh_pct"); col="$(load_colour "$p")"
    fh="${c_label}5h${c_reset} $(bar "$fh_pct" 5) ${col}${p}%${c_reset}"
    r="$(fmt_reset "$fh_reset")"; [ -n "$r" ] && fh="${fh} ${c_label}↺ ${r}${c_reset}"
    seg+=("$fh")
fi

# model · effort / fast
if [ -n "$model" ]; then
    m="${c_model}${model}${c_reset}"
    if [ -n "$fast" ] && [ "$fast" = "true" ]; then m="${m}${c_label}·${c_warn}⚡ ${c_reset}"
    elif [ -n "$effort" ] && [ "$effort" != "medium" ]; then m="${m}${c_label}·${effort}${c_reset}"; fi
    [ -n "$style" ] && [ "$style" != "default" ] && [ "$style" != "null" ] && m="${m} ${c_label}${style}${c_reset}"
    seg+=("$m")
fi

# ── emit ──────────────────────────────────────────────────
# Line 1: metrics joined with " | ". Line 2: path + branch.
sep=" ${c_label}|${c_reset} "
out=""; for s in "${seg[@]}"; do [ -n "$out" ] && out+="$sep"; out+="$s"; done
if [ -n "$out" ]; then printf '%s\n%s' "$out" "$loc"; else printf '%s' "$loc"; fi
