#!/usr/bin/env bash
# SessionStart: say what kind of repository this is, what is still open in it, and
# hand Codex the local rules it cannot read by itself.
#
# Three rules stop depending on memory here.
#
# "Look into tmp/TODO.md when starting work in a repository" is the rule that fails
# most quietly: nobody notices a note that was not read. It is one line of output.
#
# The eight repository categories used to be a paragraph the agent had to apply
# correctly. Now the category is computed and stated, once, at the top.
#
# AGENTS.local.md is read natively by Claude Code and not at all by Codex: `local.md`
# does not appear anywhere in its binary, and project_doc_fallback_filenames is not
# an overlay mechanism, it substitutes a file only where AGENTS.md is absent. So in
# Codex this hook injects the file, and the canon's rule about local rules becomes
# true in both tools without changing its wording.
#
# Output goes through hookSpecificOutput.additionalContext, which both tools deliver
# to the model as a separate developer message with no wrapper of their own. Headings
# are therefore ours to write.

set -u
HOOK_NAME="session-start"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"

hook_read_payload

CWD="$(hook_cwd)"
repo_classify "$CWD"

# --- session cache, so PreToolUse never pays for classification -----------------
write_cache() {
    local dir="$HOOK_CACHE_DIR/session" sid; sid="$(hook_session_id)"
    [ -n "$sid" ] || return 0
    mkdir -p "$dir" 2>/dev/null || return 0
    {
        printf 'REPO_ROOT=%q\n' "$REPO_ROOT"
        printf 'REPO_CATEGORY=%q\n' "$REPO_CATEGORY"
        printf 'REPO_RULES=%q\n' "$REPO_RULES"
        printf 'RULES_MINE=%q\n' "$RULES_MINE"
    } > "$dir/$sid.env" 2>/dev/null || true
    # Cheap hygiene: a machine that runs many sessions should not grow a cache
    # directory forever.
    find "$dir" -type f -mtime +7 -delete 2>/dev/null || true
}
hook_with_lock session-cache write_cache

# --- the banner -----------------------------------------------------------------
OUT=""
add() { OUT="$OUT$1
"; }

if [ -z "$REPO_ROOT" ]; then
    add "Working outside a git work tree ($CWD). Treat it as foreign: nothing is pushed, nothing of ours is left behind."
else
    add "## Repository"
    add "$(basename "$REPO_ROOT"): $(policy_summary "$REPO_CATEGORY" "$RULES_MINE")."

    policy_allow push "$REPO_CATEGORY" "$RULES_MINE" ||
        add "Push is not available here at all, whatever is asked for."
    policy_allow rules-in-git "$REPO_CATEGORY" "$RULES_MINE" ||
        add "Rules for this repository go into AGENTS.local.md only; they must not be committed."
    if [ -n "$REPO_RULES" ] && ! policy_allow rules-edit "$REPO_CATEGORY" "$RULES_MINE"; then
        add "$REPO_RULES here belongs to someone else: read it as data, never edit or tidy it."
    fi
    policy_allow gates "$REPO_CATEGORY" "$RULES_MINE" ||
        add "Do not run this project's tests or linters unless asked."

    if [ -n "$REPO_RULES_UNTRACKED" ]; then
        add "Note: $REPO_RULES_UNTRACKED exists but is not tracked by git, so it lives only on this machine and disappears on clone."
    fi
fi

# --- states that a skill handles, named out loud ---------------------------------
# A skill whose description says "when a session opens in a repository where X" never
# fires: X is a state, and nothing tells the model the state exists. An ambient
# condition is not a trigger. Whatever must fire on state has to be surfaced here, by
# the one component that can actually look.
#
# This is not a hypothetical failure mode. It was found in a neighbouring repository's
# skill, which was meant to fire on the first session in any repository where its
# choice had not been made yet, and never did in any of them.

profile="${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules/profile.json"
profile_ready=no
if [ -f "$profile" ] && hook_have_jq; then
    if [ -z "$(jq -r '[to_entries[] | select(.key | startswith("_") | not)
                       | select(.value | type == "array" and length == 0) | .key] | .[0] // ""' \
              "$profile" 2>/dev/null)" ]; then
        profile_ready=yes
    fi
fi
# These go to the nudge file rather than into the banner. The banner is reference
# material the agent consults; a nudge is something to do, and it only gets done if it
# arrives next to the owner's message. Phrased as instructions for the same reason.
# A nudge that cannot be queued goes into the banner instead. The banner is the weaker
# position, which is the whole reason the queue exists, but a rule stated weakly still
# beats a rule that vanished.
nudge_or_say() {
    hook_nudge_add "$1" && return 0
    add ""
    add "$1"
}

# Once per session is the right rhythm for this: the queue is only read on a prompt, and a
# line left by a session that never sent one has to go before an id comes back reused.
hook_nudge_sweep

if [ "$profile_ready" = "no" ]; then
    nudge_or_say "- Tell the owner in one line that the repository classifier is not configured ($profile is missing or incomplete), so the category stated at session start is a guess on the strict side and every repository reads as foreign. Offer to fix it with the rules-install skill."
fi

if [ -n "$REPO_ROOT" ] && [ -z "$REPO_RULES" ] && [ -z "$REPO_RULES_UNTRACKED" ] &&
   policy_allow rules-in-git "$REPO_CATEGORY" "$RULES_MINE"; then
    nudge_or_say "- This repository has no rules file of its own. If the work here is more than a one-off, say so in one line and offer the new-repo skill, which sets one up along with tmp/ and the gates."
fi

# --- what is still open ---------------------------------------------------------
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/tmp/TODO.md" ]; then
    open_items="$(grep -cE '^- \[ \]' "$REPO_ROOT/tmp/TODO.md" 2>/dev/null || printf 0)"
    if [ "$open_items" -gt 0 ] 2>/dev/null; then
        add "## Open in tmp/TODO.md"
        add "$open_items unchecked item(s); first: $(grep -m1 -E '^- \[ \]' "$REPO_ROOT/tmp/TODO.md" | sed 's/^- \[ \] *//')"
    else
        heads="$(grep -m3 -E '^## ' "$REPO_ROOT/tmp/TODO.md" 2>/dev/null | sed 's/^## //' | paste -sd'; ' -)"
        [ -n "$heads" ] && { add "## Open in tmp/TODO.md"; add "$heads"; }
    fi
fi

if [ -n "$REPO_ROOT" ]; then
    [ -f "$REPO_ROOT/tmp/CONTEXT.md" ] &&
        add "tmp/CONTEXT.md exists: read it before planning, it is the current state of the work."
    plan="$(ls -1t "$REPO_ROOT"/tmp/FIX_PLAN_*.md 2>/dev/null | head -1)"
    [ -n "$plan" ] &&
        add "Current plan: tmp/$(basename "$plan")."
fi

# --- local rules, for the tool that cannot read them ----------------------------
# CLAUDECODE is set inside Claude Code, which loads these files natively. Anything
# else is assumed not to, which is the safe direction: a duplicated paragraph costs
# context, a missing one costs the rule.
if [ -z "${CLAUDECODE:-}" ] && [ -n "$REPO_ROOT" ]; then
    for f in AGENTS.local.md CLAUDE.local.md; do
        if [ -f "$REPO_ROOT/$f" ]; then
            add ""
            add "## $f (local rules, not in git)"
            add "$(cat "$REPO_ROOT/$f")"
            break
        fi
    done
fi

[ -n "$OUT" ] || hook_allow

if hook_have_jq; then
    printf '%s' "$OUT" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
else
    printf '%s' "$OUT"
fi
exit 0
