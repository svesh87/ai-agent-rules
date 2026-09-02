#!/usr/bin/env bash
# PostToolUse on an editing tool: claim the task being worked on, and measure the debt
# owed to its journal.
#
# Two jobs, both cheap, both silent.
#
# The claim. A write inside tmp/work/<task>/ stamps .session in that folder with this
# session's id and the time. That one file answers both questions nothing else could:
# which task this session is on, and whether another session is on the same one. There
# is no repository-wide context file any more, so this is what SessionStart reads to
# name the active tasks.
#
# The debt. Saving the state along the way is the rule that failed most often, and it
# failed for a reason that no wording fixes: it was expensive. So it is now cheap
# (append three lines to journal.md) and it is measured. When the count of edits since
# the journal was last written crosses a threshold, a nudge goes into the queue, and
# hooks/prompt-nudge.sh delivers it beside the owner's next message, which is the one
# position measured to actually get acted on.
#
# Edits are the measure, and the only one. A Codex payload declares `transcript_path` but
# leaves it empty, so anything read out of a transcript would work in one tool and not the other;
# the first live session then showed that a byte threshold fires long before an edit
# count does, which meant the supplement was deciding everything. See the measure below.
#
# Time is deliberately not a measure either. Three hours of reading cost nothing; twenty
# minutes of editing cost everything.
#
# What this hook cannot do is wait for compaction. PreCompact gives no turn in which to
# write a file, so the debt has to be called in before the window ends, not at its edge.

set -u
HOOK_NAME="note-bookkeeping"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"

hook_read_payload
hook_is_edit_tool || hook_allow

SID="$(hook_session_id)"
[ -n "$SID" ] || hook_allow

CWD="$(hook_cwd)"
repo_context "$CWD" "$SID"
[ -n "${REPO_ROOT:-}" ] || hook_allow
WORK_DIR="$REPO_ROOT/tmp/work"
[ -d "$WORK_DIR" ] || hook_allow

# --- the claim ------------------------------------------------------------------
# Only a path inside a task folder claims it. Everything else in the session (the code
# being changed, the documents) is attributed to whichever task is already claimed.
#
# Every path of the call, not one field: Codex's apply_patch names no `file_path` at all
# and can touch several files at once, so reading a single field meant no task was ever
# claimed there and this whole mechanism was dead in that tool. See hook_paths.
while IFS= read -r target; do
    [ -n "$target" ] || continue
    # Relative to the directory in the payload, not to wherever this hook happens to be
    # running. A patch names its files relative to the session's cwd, and resolving them
    # against the hook's own would have left the claim broken in the one tool this loop
    # was added for — which is what the selftest case caught.
    case "$target" in
        /*) ABS="$target" ;;
        *)  ABS="$CWD/$target" ;;
    esac
    ABS="$(realpath -m -- "$ABS" 2>/dev/null || printf '%s' "$ABS")"
    case "$ABS" in
        "$WORK_DIR"/*)
            rest="${ABS#"$WORK_DIR"/}"
            task="${rest%%/*}"
            if [ -n "$task" ] && [ -d "$WORK_DIR/$task" ]; then
                printf '%s\n%s\n' "$SID" "$(date +%s)" \
                    > "$WORK_DIR/$task/.session" 2>/dev/null || true
            fi ;;
    esac
done <<PATHLIST
$(hook_paths)
PATHLIST

# --- which task is ours ---------------------------------------------------------
ACTIVE=""
for d in "$WORK_DIR"/*/; do
    [ -f "${d}.session" ] || continue
    [ "$(sed -n '1p' "${d}.session" 2>/dev/null)" = "$SID" ] || continue
    ACTIVE="${d%/}"
    break
done
# No claimed task means no journal to owe anything to. An edit outside the scheme is
# not a debt; it is either a two-line fix or work that has not been set up yet, and
# nagging about the second is the job of the banner, not of this hook.
[ -n "$ACTIVE" ] || hook_allow

# --- the measure ----------------------------------------------------------------
# One measure: calls to an editing tool since the journal was last written.
#
# It started as two, with the transcript's growth in bytes as a supplement, and the
# first live session settled that. Both thresholds fired on the byte count — the first
# at six edits, the second at twenty — because 150 KB of transcript goes by in a few
# calls. So the supplement was doing all the work while edits, the measure that was
# supposed to be primary, never got near its number.
#
# Removing it rather than raising it is the point. There is no transcript in a Codex
# payload, so a byte threshold that fires first in Claude Code means the two tools
# behave differently: one nags about the volume of the conversation, the other about the
# volume of the work, and each needs calibrating on its own. One measure, the same in
# both, has one number to get right.
#
# Still a first approximation, to be calibrated against real sessions.
DEBT_EDITS_1=40
DEBT_EDITS_2=80

JOURNAL="$ACTIVE/journal.md"
journal_mtime=0
[ -f "$JOURNAL" ] && journal_mtime="$(stat -c %Y "$JOURNAL" 2>/dev/null || printf 0)"

STATE="$HOOK_CACHE_DIR/session/$SID.debt"

measure() {
    local base_mtime=0 edits=0 level=0
    if [ -f "$STATE" ]; then
        base_mtime="$(sed -n '1p' "$STATE" 2>/dev/null)"
        edits="$(sed -n '2p' "$STATE" 2>/dev/null)"
        level="$(sed -n '3p' "$STATE" 2>/dev/null)"
    fi
    case "$base_mtime$edits$level" in
        ''|*[!0-9]*) base_mtime=0; edits=0; level=0 ;;
    esac

    # The journal moved: the debt is paid, and the next threshold starts from here.
    if [ "$journal_mtime" != "$base_mtime" ]; then
        base_mtime="$journal_mtime"; edits=0; level=0
    fi

    edits=$((edits + 1))

    local want=0
    if [ "$edits" -ge "$DEBT_EDITS_2" ]; then
        want=2
    elif [ "$edits" -ge "$DEBT_EDITS_1" ]; then
        want=1
    fi

    # Only on the way up, and re-armed by every reset above: the queue is cleared once
    # per prompt, so a nudge that fired at level 1 must not fire again until either the
    # journal is written or the debt reaches level 2.
    if [ "$want" -gt "$level" ]; then
        local task; task="$(basename "$ACTIVE")"
        if [ "$want" = 2 ]; then
            hook_nudge_add "- $edits edits have gone into $task since tmp/work/$task/journal.md was last written, and this is the second warning. Append to the journal now, before anything else: decisions and their reasons, measurements, traps found. Compaction gives no turn in which to write a file." ||
                hook_log "level 2 nudge for $task could not be queued"
        else
            hook_nudge_add "- $edits edits have gone into $task since tmp/work/$task/journal.md was last written. Append what would be lost with this context: why an approach was rejected, what a measurement showed, which trap was found. Three lines is a legitimate entry." ||
                hook_log "level 1 nudge for $task could not be queued"
        fi
        level="$want"
    fi

    mkdir -p "$(dirname "$STATE")" 2>/dev/null || return 0
    printf '%s\n%s\n%s\n' "$base_mtime" "$edits" "$level" > "$STATE" 2>/dev/null || true
    # Cheap hygiene, the same as the session cache: a machine running many sessions
    # should not grow this directory forever.
    find "$(dirname "$STATE")" -maxdepth 1 -name '*.debt' -mtime +7 -delete 2>/dev/null || true
}

hook_with_lock "debt-$SID" measure
exit 0
