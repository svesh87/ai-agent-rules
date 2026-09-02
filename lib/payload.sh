# Hook payload: read it, ask it questions, answer the harness.
#
# Sourced by every hook in hooks/. Claude Code and Codex send the same shape on
# stdin and accept the same answer, so nothing here reads the payload differently per
# tool: tool names are canonical in both (`Bash` for a shell command,
# `Edit`/`Write`/`apply_patch` for a file change).
#
# One thing below does distinguish the agents, and it is not about the payload:
# hook_nudge_enabled reads CLAUDECODE to pick a delivery marker, because the queue
# directory is shared between the agents while their UserPromptSubmit registrations
# are not.
#
# Two rules hold everywhere in this file.
#
# Fail open. A hook that misparses its input and blocks the call is worse than no
# hook at all: the agent loses the ability to fix the hook. Every unknown shape,
# missing tool and parse error ends in hook_allow plus a log line.
#
# Only hook_deny may exit non-zero. Nothing else in a hook script is allowed to,
# which is why `set -e` is absent by design: an unrelated failing command must not
# turn into a block. Stopping a call is not the same as exiting non-zero: hook_ask stops
# it with exit 0 and a decision in JSON, and that is the only other way out.

# Where logs go. Never inside a repository: a hook runs in foreign checkouts too,
# and dropping files there is a footprint we have no right to leave.
HOOK_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules"
HOOK_LOG="$HOOK_CACHE_DIR/hooks.log"

HOOK_JSON=""

hook_log() {
    mkdir -p "$HOOK_CACHE_DIR" 2>/dev/null || return 0
    printf '%s %s: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${HOOK_NAME:-hook}" "$*" \
        >> "$HOOK_LOG" 2>/dev/null || true
}

# Allow: silence and zero. The harness reads nothing else.
hook_allow() { exit 0; }

# Deny: reason on stderr, exit 2. This contract is verified in both tools and does
# not depend on either one's JSON schema.
hook_deny() {
    printf '%s\n' "$*" >&2
    hook_log "deny: $*"
    exit 2
}

# Warn: reason on stderr, exit 0. The agent sees the text, the call proceeds.
hook_warn() {
    printf '%s\n' "$*" >&2
    hook_log "warn: $*"
}

# Ask: stop the call and let the harness put the question to the owner.
#
# This exists because the canon says an act outside the tree happens on the owner's
# request, and until now a hook could only refuse. The refusal text even said "let them
# confirm", with nothing to confirm with: the only way through was switching every hook
# off for the whole session. The confirmation has to be the harness's, not ours, because
# a prompt the harness draws is the one thing an agent cannot answer on the owner's
# behalf. A token file in the cache would look like a barrier and be none. The write
# grants in lib/grants.sh do not contradict that line: their files are created by a hook
# out of words the owner typed into the harness's own rejection dialog, never by the
# agent, and both ways of writing them directly are stopped.
#
# The JSON form is Claude Code's documented contract. Anything else falls back to a
# refusal with the same text, and that direction is deliberate: a harness that does not
# understand the JSON sees exit 0 and lets the call through, so a guard that guessed
# wrong would be a guard that quietly allows. Codex support for the ask decision is
# unmeasured; when it is measured, this is the one place that changes.
hook_ask() {
    if [ -z "${CLAUDECODE:-}" ]; then
        hook_log "ask is unavailable here, refusing instead"
        hook_deny "$*"
    fi
    if ! hook_have_jq; then
        hook_log "ask needs jq to build its answer, refusing instead"
        hook_deny "$*"
    fi
    hook_log "ask in mode [$(hook_field '.permission_mode')]: $*"
    printf '%s' "$*" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",
        permissionDecision:"ask", permissionDecisionReason:.}}'
    exit 0
}

# Allow with an explicit decision, not silence. The difference matters exactly once:
# a documented explicit allow bypasses the harness's own permission prompt, which a
# silent exit 0 does not, and a write grant that still produced a native prompt per
# file would not have removed the clicking it exists to remove. Claude Code's contract
# only; elsewhere this degrades to the ordinary silent allow.
hook_allow_decision() {
    if [ -z "${CLAUDECODE:-}" ] || ! hook_have_jq; then
        hook_allow
    fi
    hook_log "allow decision: $*"
    printf '%s' "$*" | jq -Rs '{hookSpecificOutput:{hookEventName:"PreToolUse",
        permissionDecision:"allow", permissionDecisionReason:.}}'
    exit 0
}

hook_have_jq() { command -v jq >/dev/null 2>&1; }

# Read stdin once. Without jq we cannot parse reliably, so we allow and say so.
hook_read_payload() {
    HOOK_JSON="$(cat 2>/dev/null || true)"
    if [ -z "$HOOK_JSON" ]; then
        hook_log "empty payload, allowing"
        hook_allow
    fi
    if ! hook_have_jq; then
        hook_log "jq not installed, allowing"
        hook_allow
    fi
}

# hook_field <jq-path> — empty string when absent, malformed or null.
hook_field() {
    printf '%s' "$HOOK_JSON" | jq -r "$1 // \"\"" 2>/dev/null || printf ''
}

hook_tool()       { hook_field '.tool_name'; }
hook_event()      { hook_field '.hook_event_name'; }
hook_session_id() { hook_field '.session_id'; }

# The shell command, whichever key the tool used for it.
hook_command() {
    hook_field '.tool_input.command // .tool_input.script // .tool_input.cmd'
}

# The target path of a file-editing tool call.
hook_path() {
    hook_field '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path'
}

# The directory the session runs in. Falls back to $PWD, which a hook inherits.
hook_cwd() {
    local c
    c="$(hook_field '.cwd')"
    [ -n "$c" ] || c="$PWD"
    printf '%s' "$c"
}

# True for the tools that change files. `apply_patch` is Codex's editor; Claude
# Code sends Edit or Write. Codex accepts the latter two as matchers as well.
hook_is_edit_tool() {
    case "$(hook_tool)" in
        Edit|Write|MultiEdit|NotebookEdit|apply_patch) return 0 ;;
        *) return 1 ;;
    esac
}

hook_is_shell_tool() {
    case "$(hook_tool)" in
        Bash|shell|exec_command|local_shell) return 0 ;;
        *) return 1 ;;
    esac
}

# Nudges: things the agent should act on, delivered where they carry weight.
#
# A fact printed by SessionStart lands above the owner's first message and reads as
# background. Measured, not assumed: with the state on SessionStart an agent answered a
# greeting and said nothing about it, and when asked outright what the hook had told it,
# its first answer was "nothing" before it found the line. The same state delivered on
# UserPromptSubmit, phrased as an instruction, was acted on in the first reply.
#
# So anything that needs acting on goes into this file, and hooks/prompt-nudge.sh
# delivers it beside the owner's next message and clears it. One line per nudge, phrased
# as an instruction to the agent rather than as a fact about the world.
#
# The file is a plain append-only list keyed by session, which makes it an integration
# point rather than a private detail: any other tool's hook can add a line to it.
# The marker is written by install.sh when the delivering hook is actually registered.
# It is scoped to the active agent: a Claude hook cannot deliver a Codex queue even though
# both use the same cache directory. The generic marker is accepted only while no scoped
# marker exists, so an old installation keeps working until install.sh is run again.
# Queueing a line that nobody delivers is worse than printing it in a weak position: the
# nudge disappears entirely and the component that filed it looks like it did its job.
# That happened once already, on this machine, and cost a live regression.
HOOK_NUDGE_DIR="$HOOK_CACHE_DIR/nudge"
HOOK_NUDGE_MARKER="$HOOK_NUDGE_DIR/.delivery-enabled"
HOOK_NUDGE_CLAUDE_MARKER="$HOOK_NUDGE_DIR/.delivery-claude-enabled"
HOOK_NUDGE_CODEX_MARKER="$HOOK_NUDGE_DIR/.delivery-codex-enabled"

hook_nudge_enabled() {
    local marker
    if [ -n "${CLAUDECODE:-}" ]; then
        marker="$HOOK_NUDGE_CLAUDE_MARKER"
    else
        marker="$HOOK_NUDGE_CODEX_MARKER"
    fi

    if [ -f "$HOOK_NUDGE_CLAUDE_MARKER" ] || [ -f "$HOOK_NUDGE_CODEX_MARKER" ]; then
        [ -f "$marker" ]
    else
        [ -f "$HOOK_NUDGE_MARKER" ]
    fi
}

hook_nudge_file() {
    local sid="${1:-$(hook_session_id)}"
    [ -n "$sid" ] || return 1
    printf '%s/nudge/%s' "$HOOK_CACHE_DIR" "$sid"
}

# A queued line belongs to the prompt that comes next. A session that ends before sending
# one leaves it behind, and there were two such files on this machine from sessions that
# lived three seconds. Left alone they are not merely litter: a session id comes back when
# a session is resumed, and the line would then be delivered days late as if it were about
# the state now. Dropping a stale one costs nothing, because every nudge is derived from
# state that the next session start reads again and files again.
#
# In minutes, because that is what find takes. Markers are dotfiles and are never swept.
HOOK_NUDGE_TTL_MINUTES=1440
hook_nudge_sweep() {
    [ -d "$HOOK_NUDGE_DIR" ] || return 0
    find "$HOOK_NUDGE_DIR" -maxdepth 1 -type f ! -name '.*' \
        -mmin "+$HOOK_NUDGE_TTL_MINUTES" -delete 2>/dev/null || true
}

# Returns 0 when the line was queued, 1 when it was not. It never prints: a hook that
# builds JSON would have its output broken by a stray line, so the caller decides where an
# undeliverable nudge goes. Saying it in a weak position is right; losing it is not.
hook_nudge_add() {
    local file
    hook_nudge_enabled || return 1
    file="$(hook_nudge_file)" || return 1
    mkdir -p "$(dirname "$file")" 2>/dev/null || true
    printf '%s\n' "$*" >> "$file" 2>/dev/null || return 1
    return 0
}

# Take a lock before touching a shared file. Hooks for one event run in parallel
# in Codex, and another SessionStart hook already runs on this machine.
#
# The lock is taken on a file descriptor rather than by handing the work to flock as a
# command string. Every caller passes a shell function, and the string form runs it
# through sh, where a function of this shell does not exist: the lock was never held once,
# and every session start logged that it had fallen back to running unlocked. Waiting is
# bounded because a hook that hangs costs more than a rare interleaved write, so a lock
# that cannot be had in time is reported and the work goes ahead without it.
hook_with_lock() {
    local name="$1"; shift
    mkdir -p "$HOOK_CACHE_DIR" 2>/dev/null || { "$@"; return $?; }
    if command -v flock >/dev/null 2>&1; then
        local rc=0
        {
            flock -w 2 9 2>/dev/null || hook_log "lock timed out for $name, ran unlocked"
            "$@" || rc=$?
        } 9>"$HOOK_CACHE_DIR/$name.lock"
        return $rc
    fi
    "$@"
}
