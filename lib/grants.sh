# Time-boxed write grants: the owner's answer to "may this write land outside the
# work tree", extended in time instead of asked again per file.
#
# A grant is one file under $XDG_CACHE_HOME/agent-rules/grants/: line 1 the resolved
# path prefix it covers, line 2 the epoch second it expires at, line 3 where it came
# from, for the log and for doctor.sh. Expired grants are dropped on every read, so
# nothing needs to run on a schedule.
#
# Grants are created in exactly one place, guard-write-scope.sh, and only out of words
# the owner typed into the harness's own rejection dialog. That is what keeps this from
# being the token file lib/payload.sh warns about: the harness writes the owner's words
# into the transcript, an agent cannot put them there, and the two ways an agent could
# write this directory directly are both stopped — an editing tool lands on the
# outside-the-tree ask, and a shell write toward it is refused by guard-shell-edit.sh.

GRANTS_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/grants"
GRANT_MAX_MINUTES=480

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
