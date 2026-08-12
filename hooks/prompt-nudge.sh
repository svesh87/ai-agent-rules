#!/usr/bin/env bash
# UserPromptSubmit: deliver what the agent should act on, next to the owner's message.
#
# This hook exists because of a measured failure. A state announced by SessionStart lands
# above the owner's first message, and an agent treated it as background: it answered a
# greeting without mentioning it, and when asked point blank what the SessionStart hook
# had told it, answered "nothing" before finding the line. The same state delivered here,
# phrased as an instruction, was acted on in the first reply.
#
# The position is the whole point. Output from this event arrives beside the prompt, at
# the end of the context, where weight is highest — the opposite end from the always
# loaded rules text, which is the weakest place anything can sit.
#
# Delivered once per session and then cleared, because a line repeated on every prompt
# stops being read after the second time.

set -u
HOOK_NAME="prompt-nudge"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"

hook_read_payload

FILE="$(hook_nudge_file)" || hook_allow
[ -s "$FILE" ] || hook_allow

deliver() {
    local body; body="$(cat "$FILE" 2>/dev/null)"
    [ -n "$body" ] || return 0
    # Cleared before printing, not after: a crash between the two would repeat the nudge
    # on every prompt for the rest of the session, which is worse than losing it once.
    : > "$FILE" 2>/dev/null || true

    local text
    text="$(printf 'Before answering, deal with this. It is about the state of this repository, not about the message itself:\n%s' "$body")"

    if hook_have_jq; then
        printf '%s' "$text" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
    else
        printf '%s\n' "$text"
    fi
}

hook_with_lock "nudge-$(hook_session_id)" deliver
exit 0
