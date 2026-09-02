# Time-boxed write grants: the owner's answer to "may this write land outside the
# work tree", extended in time instead of asked again per file.
#
# A grant is one file under $XDG_CACHE_HOME/agent-rules/grants/: line 1 the resolved
# path prefix it covers, line 2 the epoch second it expires at, line 3 where it came
# from, for the log and for doctor.sh. Expired grants are dropped on every read, so
# nothing needs to run on a schedule.
#
# Grants are created in two places and only ever out of words the owner typed into the
# harness itself: guard-write-scope.sh reads the rejection dialog through the transcript
# in Claude Code, and prompt-nudge.sh reads the next chat message in Codex, which has no
# dialog of ours to answer because its runtime rejects an ask decision outright.
#
# That is what keeps this from being the token file lib/payload.sh warns about. In both
# channels the harness writes the owner's words — into the transcript, or into the
# `prompt` field of a UserPromptSubmit payload — and an agent cannot put them there. And
# the two ways an agent could write this directory directly are both stopped: an editing
# tool lands on the outside-the-tree ask, and a shell write toward it is refused by
# guard-shell-edit.sh.

GRANTS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/grants"
GRANT_MAX_MINUTES=480

# The scope of the write that was just refused, remembered so that an answer arriving
# afterwards knows what it is answering about. One record per session, overwritten by the
# next refusal, which is what makes "the phrase answers the refusal you just saw" true
# without keeping a queue.
#
# Two channels read it and they differ only in where the owner's words come from. In
# Claude Code it is the rejection dialog, whose text reaches the hook through the
# transcript in a wrapper the harness writes. In Codex there is no such dialog at all —
# an ask decision is rejected by its runtime as unsupported — so the words come from the
# next chat message, on `UserPromptSubmit`, where the payload's `prompt` is written by the
# harness and cannot be forged by the agent.
#
# The window is short on purpose: a phrase is an answer to something, and an answer that
# arrives ten minutes later is answering nothing.
GRANT_ASKED_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/asked"
GRANT_ASK_WINDOW_SECONDS=600

# grant_asked_record <session> <scope> — remember what was just refused.
grant_asked_record() {
    [ -n "${1:-}" ] || return 0
    mkdir -p "$GRANT_ASKED_DIR" 2>/dev/null || return 0
    printf '%s\n%s\n' "$2" "$(date +%s)" > "$GRANT_ASKED_DIR/$1" 2>/dev/null || true
}

# grant_asked_scope <session> — print the remembered scope while it is still fresh.
# Fails on anything unexpected, because every failure here has to end in a question
# rather than in a grant.
grant_asked_scope() {
    local file="$GRANT_ASKED_DIR/${1:-}" scope at
    [ -n "${1:-}" ] && [ -f "$file" ] || return 1
    scope="$(sed -n '1p' "$file" 2>/dev/null)"
    at="$(sed -n '2p' "$file" 2>/dev/null)"
    [ -n "$scope" ] || return 1
    case "$at" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ $(( $(date +%s) - at )) -le "$GRANT_ASK_WINDOW_SECONDS" ] || return 1
    printf '%s' "$scope"
}

# grant_asked_at <session> — the epoch second of the remembered refusal, for a caller
# that needs to compare it against the timestamp of the owner's words.
grant_asked_at() {
    local at
    at="$(sed -n '2p' "$GRANT_ASKED_DIR/${1:-}" 2>/dev/null)"
    case "$at" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s' "$at"
}

grant_asked_clear() {
    [ -n "${1:-}" ] || return 0
    rm -f "$GRANT_ASKED_DIR/$1" 2>/dev/null || true
}

# grant_sweep — drop expired or malformed grants.
grant_sweep() {
    [ -d "$GRANTS_DIR" ] || return 0
    local f exp now
    now="$(date +%s)"
    for f in "$GRANTS_DIR"/*.grant; do
        [ -f "$f" ] || continue
        exp="$(sed -n '2p' "$f" 2>/dev/null)"
        case "$exp" in
            ''|*[!0-9]*) rm -f "$f"; continue ;;
        esac
        [ "$exp" -le "$now" ] && rm -f "$f"
    done
    return 0
}

# grant_match <resolved path> — succeeds when a live grant covers the path, printing
# the prefix it matched. The caller resolves the path; prefixes are stored resolved.
grant_match() {
    local path="$1" f pfx
    grant_sweep
    [ -d "$GRANTS_DIR" ] || return 1
    for f in "$GRANTS_DIR"/*.grant; do
        [ -f "$f" ] || continue
        pfx="$(sed -n '1p' "$f" 2>/dev/null)"
        [ -n "$pfx" ] || continue
        case "$path" in
            "$pfx"|"$pfx"/*) printf '%s' "$pfx"; return 0 ;;
        esac
    done
    return 1
}

# grant_create <resolved prefix> <minutes> <source>
grant_create() {
    local pfx="$1" mins="$2" src="$3"
    mkdir -p "$GRANTS_DIR" 2>/dev/null || return 1
    printf '%s\n%s\n%s\n' "$pfx" "$(( $(date +%s) + mins * 60 ))" "$src" \
        > "$GRANTS_DIR/$(date +%s%N).grant" 2>/dev/null
}

# grant_scope_of <resolved path> — the prefix a grant for this path covers: the root
# of the git work tree the path is in, or its directory when it is in none. A grant
# for one file would just move the clicking one level down; the repository is the
# unit the owner reasons in ("writes in grafana for an hour").
grant_scope_of() {
    local p="$1" d r
    d="$p"
    [ -d "$d" ] || d="$(dirname "$p")"
    r="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$r" ] || r="$d"
    if command -v realpath >/dev/null 2>&1; then
        r="$(realpath -m "$r" 2>/dev/null || printf '%s' "$r")"
    fi
    printf '%s' "$r"
}

# grant_phrase_minutes <text> — the minutes a phrase asks for, or failure when the
# text is not exactly a grant phrase. The whole message must be the phrase: a pasted
# paragraph that merely contains one grants nothing. The forms are the ones the ask
# text offers plus what the owner actually typed the first times this ran live — an
# optional «аппрув» or «разрешаю» in front, and hours as well as minutes: «на час»,
# «аппрув на 2 минуты», «разрешаю на 10 минут», «на N минут», «аппрув на N часов».
# Everything is capped at GRANT_MAX_MINUTES.
grant_phrase_minutes() {
    local t n
    t="$(printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g; s/^([аА]ппрув|[рР]азрешаю) //')"
    case "$t" in
        'на час'|'На час') printf '60'; return 0 ;;
    esac
    n="$(printf '%s' "$t" | sed -nE 's/^[нН]а ([0-9]{1,3}) минут(ы|у)?$/\1/p')"
    if [ -z "$n" ]; then
        n="$(printf '%s' "$t" | sed -nE 's/^[нН]а ([0-9]{1,2}) час(а|ов)?$/\1/p')"
        [ -n "$n" ] || return 1
        n=$(( n * 60 ))
    fi
    [ "$n" -ge 1 ] && [ "$n" -le "$GRANT_MAX_MINUTES" ] || return 1
    printf '%s' "$n"
}

# grant_rejection_feedback <transcript path> — what the owner typed into the harness's
# rejection dialog, from the newest such entry in the tail of the transcript, printed
# as "<iso-timestamp>\t<text>". The wrapper around the text is written by the harness,
# never by the agent, which is what makes this a channel worth trusting. Any parse
# trouble prints nothing, and the caller falls back to asking — the failure direction
# here must never be an allow.
grant_rejection_feedback() {
    local tp="$1"
    [ -f "$tp" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    tail -n 200 "$tp" 2>/dev/null | jq -r '
        select(.type == "user")
        | (.timestamp // "") as $ts
        | .message.content[]?
        | select(.type == "tool_result")
        | (if (.content | type) == "string" then .content
           elif (.content | type) == "array"
           then ([.content[]? | select(.type == "text") | .text] | join("\n"))
           else "" end)
        | select(test("The user provided the following reason for the rejection:"))
        | sub(".*The user provided the following reason for the rejection:[[:space:]]*"; "")
        | $ts + "\t" + .
    ' 2>/dev/null | tail -n 1
}
