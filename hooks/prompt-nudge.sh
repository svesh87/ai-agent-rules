#!/usr/bin/env bash
# UserPromptSubmit: deliver what the agent should act on, next to the owner's message, and
# turn the owner's own words into a write grant where no other channel can.
#
# Two duties, and the first one is why this hook exists at all.
#
# **Delivery.** A state announced by SessionStart lands above the owner's first message and
# reads as background: an agent answered a greeting without mentioning it, and when asked
# point blank what the SessionStart hook had told it, answered "nothing" before finding the
# line. The same state delivered here, phrased as an instruction, was acted on in the first
# reply. The position is the whole point — output from this event arrives beside the prompt,
# at the end of the context, where weight is highest, the opposite end from the always
# loaded rules text.
#
# Delivered once per session and then cleared, because a line repeated on every prompt
# stops being read after the second time.
#
# **The owner's yes, in Codex.** In Claude Code an ask decision reaches the owner as a
# permission prompt, and a phrase typed into its rejection field becomes a time-boxed write
# grant. Codex has no such dialog: its runtime answers an ask with `PreToolUse hook returned
# unsupported permissionDecision:ask` and marks the hook failed, which makes it discard our
# verdict entirely. So there the only shape our decision survives in is a refusal — and a
# refusal with no way to answer it leaves the owner unable to approve a write outside the
# tree at all.
#
# This is that way. `guard-write-scope.sh` remembers the scope it just refused; if the
# owner's very next message is exactly a grant phrase, the grant is minted here and the
# retry passes. The trust rests on the same property as the Claude channel: the payload's
# `prompt` is written by the harness, and an agent cannot put a message from the owner into
# it. Measured, not assumed: `prompt` is a required field of
# `user-prompt-submit.command.input` in Codex's own schema, which its binary carries.
#
# Deliberately narrow. Only outside Claude Code, where the other channel already exists.
# Only a message that is nothing but the phrase, so that a phrase quoted inside a sentence
# grants nothing. Only against a refusal from the last ten minutes, so that a phrase is an
# answer to something. Only for the scope that was refused, and never for deletion or
# anything in guard-destructive.sh.

set -u
HOOK_NAME="prompt-nudge"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/grants.sh
. "$HERE/../lib/grants.sh"

hook_read_payload

SID="$(hook_session_id)"

# The owner's yes. Prints the line to tell the agent, or nothing.
chat_grant() {
    local prompt scope mins
    [ -z "${CLAUDECODE:-}" ] || return 0
    [ -n "$SID" ] || return 0
    prompt="$(hook_field '.prompt')"
    [ -n "$prompt" ] || return 0
    mins="$(grant_phrase_minutes "$prompt")" || return 0
    scope="$(grant_asked_scope "$SID")" || {
        hook_log "grant phrase with no fresh refusal to answer, ignored"
        return 0
    }
    grant_create "$scope" "$mins" "owner's phrase in the Codex chat, session $SID"
    grant_asked_clear "$SID"
    hook_log "grant from chat: $scope for $mins minutes"
    printf -- '- The owner just granted writes in %s for %s minutes. Retry the write that was refused, once. Do not treat this as permission for anything else: deletions, moves and everything in the destructive guard are still decided one at a time.\n' \
        "$scope" "$mins"
}

deliver() {
    local granted queued body text file
    granted="$(chat_grant)"

    file="$(hook_nudge_file "$SID" 2>/dev/null || printf '')"
    queued=""
    if [ -n "$file" ] && [ -s "$file" ]; then
        queued="$(cat "$file" 2>/dev/null)"
        # Cleared before printing, not after: a crash between the two would repeat the
        # nudge on every prompt for the rest of the session, which is worse than losing
        # it once.
        : > "$file" 2>/dev/null || true
    fi

    body="$granted$queued"
    [ -n "$body" ] || return 0

    text="$(printf 'Before answering, deal with this. It is about the state of this repository, not about the message itself:\n%s' "$body")"

    if hook_have_jq; then
        printf '%s' "$text" | jq -Rs '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:.}}'
    else
        printf '%s\n' "$text"
    fi
}

hook_with_lock "nudge-$SID" deliver
exit 0
