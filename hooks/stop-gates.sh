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
# The third is the state of the active task, and this hook is one of its two entrances:
# `scripts/task.sh check` holds the logic, the `handover` skill calls it by hand, and the
# hook calls it here so that nobody has to remember to. It reports the declared
# deliverables the spec names and the working tree does not show as touched — the
# secondary ones included, a skill to be filled in along the way, a document, a change to
# the rules, which are exactly what the main work starves — plus a spec edited after it
# was approved, a status line that no longer matches the approvals, and a template's
# language switch left at the top of a document.
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

TASK_SH="$HERE/../scripts/task.sh"
if [ -n "$ACTIVE" ] && [ -x "$TASK_SH" ]; then
    # --quiet prints findings and nothing else, so an empty answer means a clean task.
    # The open checkboxes of tasks.md are left out on purpose: mid-task an open item is
    # the normal state, and a warning that fires on every Stop for it is a warning nobody
    # reads by the third day. The `handover` skill passes --handover and gets them.
    #
    # A script that failed rather than reported is not a finding: in Codex a hook that
    # exits non-zero is discarded along with its verdict, so an error here must not turn
    # into the appearance of a clean tree. Findings and failures both arrive as text, and
    # only the text is used.
    TASK_FINDINGS="$("$TASK_SH" check "$ACTIVE" --quiet 2>/dev/null || true)"
    [ -n "$TASK_FINDINGS" ] && MSG="${MSG:+$MSG
}$TASK_FINDINGS"
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
