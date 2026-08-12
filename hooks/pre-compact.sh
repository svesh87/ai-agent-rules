#!/usr/bin/env bash
# PreCompact: the context is about to be summarised. Say what will be lost.
#
# The rule is "before stopping for review, move into files whatever would be lost with
# the context", and the moment it matters most is the one moment the agent cannot see
# coming. "Compaction ahead" was a line in a skill description, which means it never
# fired: a state nothing announces is not a trigger.
#
# This hook is the announcement. It says nothing about what to write, because the
# context-snapshot skill already covers that; it only makes the moment observable.

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

MSG="The context is about to be compacted. Anything that exists only in this
conversation is about to become a summary of itself: measurements, decisions and their
reasons, traps found, the next concrete step. Write it to files first, and use the
context-snapshot skill for tmp/CONTEXT.md."

if [ ! -f "$REPO_ROOT/tmp/CONTEXT.md" ]; then
    MSG="$MSG
There is no tmp/CONTEXT.md in this repository yet, so nothing has been written down so far."
else
    age="$(( ( $(date +%s) - $(stat -c %Y "$REPO_ROOT/tmp/CONTEXT.md" 2>/dev/null || date +%s) ) / 60 ))"
    MSG="$MSG
tmp/CONTEXT.md was last written $age minute(s) ago; check whether it still describes the work."
fi

if hook_have_jq; then
    printf '%s' "$MSG" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreCompact",additionalContext:.}}'
else
    printf '%s\n' "$MSG"
fi
exit 0
