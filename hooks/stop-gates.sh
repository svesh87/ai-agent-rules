#!/usr/bin/env bash
# Stop: before the turn ends, check what the canon says must be checked.
#
# Four things, all cheap and all easy to forget after a long session.
#
# `git diff --check` catches whitespace damage and conflict markers. It is in the
# canon as part of every handover and it costs milliseconds.
#
# The second is a reminder, not a verdict: if the work tree changed and no test or
# lint command ran in this session, say so. The hook cannot know a project's gates,
# and inventing them would be worse than asking, so it only points.
#
# The third is the declared deliverables. The spec of the active task names them, the
# secondary ones included — a skill to be filled in along the way, a document, a change
# to the rules — and those are exactly what the main work starves. A path the spec names
# that does not appear in `git status` was not touched, and saying so here is what stops
# the owner from having to remember it.
#
# The fourth is bookkeeping debt at its second threshold. hooks/note-bookkeeping.sh
# queues a nudge for the next prompt; if the turn is ending with the debt still doubled,
# the journal is about to be a session behind.
#
# This hook never blocks. A Stop hook that refuses to let a turn end turns a warning
# into a trap, and the operator, not the hook, decides when work is finished. That is
# also why the debt tops out at a warning: it was considered as a block and rejected.

set -u
HOOK_NAME="stop-gates"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"

hook_read_payload

CWD="$(hook_cwd)"
repo_context "$CWD" "$(hook_session_id)"
[ -n "${REPO_ROOT:-}" ] || hook_allow

MSG=""

check="$(git -C "$REPO_ROOT" diff --check 2>/dev/null || true)"
if [ -n "$check" ]; then
    MSG="git diff --check is not clean:
$(printf '%s' "$check" | head -5)"
fi

# Did anything change at all?
dirty="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -vE '^\?\? tmp/' | head -1 || true)"
if [ -n "$dirty" ] && policy_allow gates "${REPO_CATEGORY:-none}" "${RULES_MINE:-na}"; then
    marker="$HOOK_CACHE_DIR/session/$(hook_session_id).gates"
    if [ ! -f "$marker" ]; then
        MSG="${MSG:+$MSG
}The work tree changed and no test or lint command ran in this session. Before handing over: run this project's gates, then the consistency pass."
    fi
fi

# The active task, claimed by this session's writes into its folder. Same lookup as
# note-bookkeeping.sh, which is the hook that stamps the claim.
ACTIVE=""
SID="$(hook_session_id)"
if [ -n "$SID" ] && [ -d "$REPO_ROOT/tmp/work" ]; then
    for d in "$REPO_ROOT"/tmp/work/*/; do
        [ -f "${d}.session" ] || continue
        [ "$(sed -n '1p' "${d}.session" 2>/dev/null)" = "$SID" ] || continue
        ACTIVE="${d%/}"
        break
    done
fi

if [ -n "$ACTIVE" ] && [ -f "$ACTIVE/spec.md" ] && [ -n "$dirty" ]; then
    # Paths in backticks under the deliverables heading, in either language. A token has
    # to carry a file extension to count, which is what keeps `tmp/` and a mention of
    # `git status` in the prose from being read as deliverables.
    declared="$(awk '
        /^#+[[:space:]]*(Deliverables|Деливераблы)/ { inside = 1; next }
        /^#+[[:space:]]/ { inside = 0 }
        inside { print }
    ' "$ACTIVE/spec.md" 2>/dev/null | grep -oE '`[A-Za-z0-9_./-]+\.[A-Za-z0-9]+`' |
        tr -d '`' | sort -u)"
    changed="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | sed -E 's/^.{3}//')"
    untouched=""
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        # Two shapes of entry, and the second one is why comparing strings was wrong:
        # git collapses a wholly untracked directory into one line ending in `/`, so a
        # brand new `skills/thing/SKILL.md` appears only as `skills/thing/`. Matching
        # only the exact path would report every new file as untouched forever, which
        # is the noisiest way a reminder can lose its credibility.
        touched=""
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            case "$entry" in
                */) case "$path" in "$entry"*) touched=1 ;; esac ;;
                *)  [ "$entry" = "$path" ] && touched=1 ;;
            esac
            [ -n "$touched" ] && break
        done <<ENTRIES
$changed
ENTRIES
        [ -n "$touched" ] && continue
        untouched="${untouched:+$untouched, }$path"
    done <<EOF
$declared
EOF
    [ -n "$untouched" ] && MSG="${MSG:+$MSG
}The spec of $(basename "$ACTIVE") declares deliverables that the working tree does not show as touched: $untouched. Work is not done while a declared deliverable is untouched."
fi

if [ -n "$ACTIVE" ] && [ -n "$SID" ]; then
    state="$HOOK_CACHE_DIR/session/$SID.debt"
    if [ -f "$state" ] && [ "$(sed -n '3p' "$state" 2>/dev/null)" = 2 ]; then
        MSG="${MSG:+$MSG
}Bookkeeping debt is at its second threshold: $(sed -n '2p' "$state") edits since tmp/work/$(basename "$ACTIVE")/journal.md was written. Append to it before the turn ends; compaction gives no turn in which to write a file."
    fi
fi

[ -n "$MSG" ] || hook_allow
hook_warn "$MSG"
exit 0
