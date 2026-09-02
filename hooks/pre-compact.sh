#!/usr/bin/env bash
# PreCompact: the context is about to be summarised. Say what is about to be lost, and
# say it honestly — this hook is a last note, not a safety net.
#
# It used to read as the net. It cannot be one: PreCompact gives no turn in which to
# write a file, so an agent that was saving its state "before compaction" was saving it
# never, and the loss the rule exists to prevent happened at exactly the moment the rule
# was supposed to fire. That is why the debt is now measured and called in early by
# hooks/note-bookkeeping.sh, and why what is left for this hook is to shape the summary.
#
# So the text points at the journal of the active task and says what belongs in a
# summary if it did not make it into a file. Nothing here asks for a write that cannot
# happen.

set -u
HOOK_NAME="pre-compact"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"

hook_read_payload

CWD="$(hook_cwd)"
repo_context "$CWD" "$(hook_session_id)"
[ -n "${REPO_ROOT:-}" ] || hook_allow

MSG="The context is about to be compacted, and this hook gives no turn in which to write
a file: whatever exists only in this conversation is now either in the summary or gone.
Carry the expensive parts into it — why an approach was rejected, what a measurement
showed, which trap was found, the next concrete step — and append them to the journal in
the first turn after the summary, with the context-snapshot skill."

# The active task, claimed by this session's writes into its folder (see
# hooks/note-bookkeeping.sh). Naming the file beats naming the skill: the next turn
# starts with a path rather than a lookup.
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

if [ -n "$ACTIVE" ]; then
    task="$(basename "$ACTIVE")"
    if [ -f "$ACTIVE/journal.md" ]; then
        age="$(( ( $(date +%s) - $(stat -c %Y "$ACTIVE/journal.md" 2>/dev/null || date +%s) ) / 60 ))"
        MSG="$MSG
The active task is tmp/work/$task; its journal.md was last written $age minute(s) ago."
    else
        MSG="$MSG
The active task is tmp/work/$task and it has no journal.md yet, so nothing has been written down so far."
    fi
else
    MSG="$MSG
No task in tmp/work/ is claimed by this session, so there is no journal to append to and nothing has been written down so far."
fi

if hook_have_jq; then
    printf '%s' "$MSG" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreCompact",additionalContext:.}}'
else
    printf '%s\n' "$MSG"
fi
exit 0
