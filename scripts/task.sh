#!/usr/bin/env bash
# The task lifecycle, as far as it can be made mechanical: create, approve, check.
#
# The scheme had genres and two approvals and not one executable step, so everything it
# asked for was a promise: copy the templates by hand, approve in the right order, keep
# the status line true, notice when the spec drifted away from what was built. Promises
# of that shape survive two tasks. These three subcommands are the parts a script can
# hold instead.
#
#   new     the folder and the documents, one stage at a time. `plan.md` is refused until
#           the spec is approved and `tasks.md` until the plan is, because the sequence is
#           the point: a spec written after the code is a report, and the first two tasks
#           under this scheme both produced one.
#   approve the owner's yes as a dated line in `.approvals`, plus the status line stamped
#           to match.
#   check   the five states that are wrong no matter who says otherwise.
#
# `.approvals` is bookkeeping, not a trust boundary. The agent runs this script, so the
# agent can write that line itself — the same reason a grant minted from the terminal was
# rejected for Codex in favour of the owner's own message. What it buys is that an
# approval exists as a dated record instead of a memory, and that the status line has one
# author. It buys nothing against an agent that lies.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$HERE/../templates/work"
TODAY="$(date '+%Y-%m-%d')"

die() { printf '%s\n' "$*" >&2; exit 1; }

usage() {
    cat >&2 <<'USAGE'
usage:
  task.sh new <slug> [--lang ru|en]         tmp/work/<date>-<slug>/ with spec.md and journal.md
  task.sh new --plan|--tasks [<task>]       the next document, once its predecessor is approved
  task.sh approve spec|plan [<task>]        record the owner's approval, stamp the status line
  task.sh check [<task>] [--quiet] [--handover]
                                            findings on stdout, exit 1 if there are any

A <task> is the path of a task folder. Left out, it is taken from the current directory
when that sits inside one.
USAGE
    exit 2
}

# ------------------------------------------------------------------ shared

repo_root() { git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null; }

# The task folder holding a path, or nothing. tmp/work/<name>/ is the only shape.
task_of_path() {
    local dir="$1"
    dir="$(cd "$dir" 2>/dev/null && pwd)" || return 0
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        case "$dir" in
            */tmp/work/*) [ "$(basename "$(dirname "$dir")")" = work ] && { printf '%s' "$dir"; return 0; } ;;
        esac
        dir="$(dirname "$dir")"
    done
}

resolve_task() {
    local given="${1:-}"
    if [ -n "$given" ]; then
        [ -d "$given" ] || die "no such task folder: $given"
        (cd "$given" && pwd)
        return 0
    fi
    local found; found="$(task_of_path .)"
    [ -n "$found" ] || die "no task folder given, and the current directory is not inside one"
    printf '%s' "$found"
}

status_line() { grep -m1 -E '^\*\*(Статус|Status):\*\*' "$1" 2>/dev/null; }

# The state is the first word after the colon; the rest of the line stays free text.
# Russian endings vary (одобрен, одобрена, одобрено), so a stem is matched rather than a
# word, and both cases are listed because tolower() folds ASCII only.
status_state() {
    local word
    word="$(status_line "$1" |
        sed -E 's/^\*\*(Статус|Status):\*\*[[:space:]]*//' |
        awk '{print $1}' | tr -d ',.:;')"
    case "$word" in
        ""|"<"*)                 printf 'none' ;;
        черновик*|Черновик*|draft*|Draft*)     printf 'draft' ;;
        одобр*|Одобр*|approv*|Approv*)         printf 'approved' ;;
        исполн*|Исполн*|сдан*|Сдан*|done*|Done*) printf 'done' ;;
        *)                       printf 'unknown' ;;
    esac
}

# ru or en, taken from whichever document already exists. A task does not mix the two.
task_lang() {
    local task="$1" f
    for f in spec.md plan.md tasks.md journal.md; do
        [ -f "$task/$f" ] || continue
        case "$(status_line "$task/$f")" in
            *"Статус"*) printf 'ru'; return 0 ;;
            *"Status"*) printf 'en'; return 0 ;;
        esac
        grep -qE '^# (Журнал|Задачи)' "$task/$f" && { printf 'ru'; return 0; }
        grep -qE '^# (Journal|Tasks)' "$task/$f" && { printf 'en'; return 0; }
    done
    printf ''
}

# The template's first line switches between the two copies of the template itself. It is
# not part of the shape, and it reached four files of a real task before anyone noticed.
place_template() {
    # Every argument of `local` is expanded before any of them is assigned, so src is
    # built on its own line rather than beside the name it needs.
    local name="$1" lang="$2" dest="$3" src
    src="$TEMPLATES/$name"
    [ "$lang" = ru ] && src="$TEMPLATES/${name%.md}.ru.md"
    [ -f "$src" ] || die "no template at $src"
    [ -e "$dest" ] && die "$dest exists already"
    awk -v today="$TODAY" '
        NR == 1 && /^\*(\[English\]|English )/ { skip_blank = 1; next }
        skip_blank && /^[[:space:]]*$/ { skip_blank = 0; next }
        { skip_blank = 0; gsub(/<YYYY-MM-DD>/, today); print }
    ' "$src" > "$dest" || die "could not write $dest"
}

approvals_file() { printf '%s/.approvals' "$1"; }

# Epoch of the last approval of one document, or 0.
approved_at() {
    local file; file="$(approvals_file "$1")"
    [ -f "$file" ] || { printf 0; return 0; }
    awk -v k="$2" '$1 == k { t = $2 } END { printf "%d", t + 0 }' "$file"
}

# ------------------------------------------------------------------ new

cmd_new() {
    local slug="" lang="" what="task" arg
    while [ $# -gt 0 ]; do
        arg="$1"; shift
        case "$arg" in
            --plan)  what="plan" ;;
            --tasks) what="tasks" ;;
            --lang)  lang="${1:-}"; shift || true ;;
            -*)      usage ;;
            *)       [ -z "$slug" ] && slug="$arg" || usage ;;
        esac
    done
    case "$lang" in ru|en|"") ;; *) die "--lang takes ru or en" ;; esac

    if [ "$what" = task ]; then
        [ -n "$slug" ] || usage
        case "$slug" in */*|"") die "a slug is one path segment: letters, digits and dashes" ;; esac
        local root; root="$(repo_root .)" || true
        [ -n "$root" ] || die "not inside a git repository"
        local task="$root/tmp/work/$TODAY-$slug"
        [ -e "$task" ] && die "$task exists already"
        mkdir -p "$task" || die "could not create $task"
        [ -n "$lang" ] || lang=ru
        place_template spec.md "$lang" "$task/spec.md"
        place_template journal.md "$lang" "$task/journal.md"
        printf '%s\n' "$task"
        printf 'spec.md and journal.md are in place. The measurement goes into the journal\n'
        printf 'first where the unknown is how something behaves; the spec is written after it.\n'
        printf 'Next: task.sh approve spec, then task.sh new --plan\n'
        return 0
    fi

    # die() inside a command substitution ends the subshell and nothing else, so every
    # call site has to carry the failure out itself.
    local task; task="$(resolve_task "$slug")" || exit 1
    [ -n "$lang" ] || lang="$(task_lang "$task")"
    [ -n "$lang" ] || lang=ru
    if [ "$what" = plan ]; then
        # A spec that exists must be approved first. A task with no spec at all is the
        # owner's call — they asked for a plan and nothing else, and that happens — so it
        # is allowed and said out loud, because it is also the shape that loses the
        # deliverable and acceptance checks entirely.
        if [ -f "$task/spec.md" ]; then
            [ "$(approved_at "$task" spec)" -gt 0 ] ||
                die "spec.md is not approved yet: the plan is written against an approved spec.
Record the owner's approval with: task.sh approve spec $task"
        fi
        place_template plan.md "$lang" "$task/plan.md"
        printf '%s/plan.md\n' "$task"
        [ -f "$task/spec.md" ] ||
            printf 'no spec.md in this task: nothing declares deliverables or acceptance,\nso check has nothing to read for either.\n'
    else
        [ -f "$task/plan.md" ] || die "no plan.md in $task"
        [ "$(approved_at "$task" plan)" -gt 0 ] ||
            die "plan.md is not approved yet: a checklist built ahead of the plan gets
rewritten the moment the plan changes. Record the approval with: task.sh approve plan $task"
        place_template tasks.md "$lang" "$task/tasks.md"
        printf '%s/tasks.md\n' "$task"
    fi
}

# ------------------------------------------------------------------ approve

cmd_approve() {
    local what="${1:-}"; shift || true
    case "$what" in spec|plan) ;; *) usage ;; esac
    local task; task="$(resolve_task "${1:-}")" || exit 1
    local doc="$task/$what.md"
    [ -f "$doc" ] || die "no $what.md in $task"
    [ "$what" = plan ] && [ -f "$task/spec.md" ] && [ "$(approved_at "$task" spec)" -eq 0 ] &&
        die "spec.md is not approved: approve it first, or the plan is approved against nothing"

    local now; now="$(date '+%s')"
    printf '%s %s %s\n' "$what" "$now" "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$(approvals_file "$task")" ||
        die "could not write $(approvals_file "$task")"

    # One author for the status line, which is why it can be trusted to match .approvals.
    local lang; lang="$(task_lang "$task")"; [ -n "$lang" ] || lang=ru
    local replacement
    if [ "$lang" = ru ]; then
        replacement="**Статус:** одобрено владельцем $TODAY"
    else
        replacement="**Status:** approved by the owner $TODAY"
    fi
    local tmp="$doc.status.$$"
    awk -v line="$replacement" '
        !done_it && /^\*\*(Статус|Status):\*\*/ { print line; done_it = 1; next }
        { print }
    ' "$doc" > "$tmp" && mv "$tmp" "$doc" || { rm -f "$tmp"; die "could not stamp the status line in $doc"; }

    printf '%s approved, %s\n' "$what.md" "$TODAY"
    [ "$what" = spec ] && printf 'Next: task.sh new --plan %s\n' "$task"
    [ "$what" = plan ] && printf 'Next: task.sh new --tasks %s\n' "$task"
    return 0
}

# ------------------------------------------------------------------ check

FINDINGS=""
NOTE=""
finding() { FINDINGS="${FINDINGS:+$FINDINGS
}$1"; }

# Paths in backticks under the deliverables heading, in either language. A token has to
# carry a file extension to count, which is what keeps `tmp/` and a mention of
# `git status` in the prose from being read as deliverables.
declared_deliverables() {
    awk '
        /^#+[[:space:]]*(Deliverables|Деливераблы)/ { inside = 1; next }
        /^#+[[:space:]]/ { inside = 0 }
        inside { print }
    ' "$1" 2>/dev/null | grep -oE '`[A-Za-z0-9_./-]+\.[A-Za-z0-9]+`' | tr -d '`' | sort -u
}

check_deliverables() {
    local task="$1" root="$2" name="$3"
    [ -f "$task/spec.md" ] || return 0
    local porcelain; porcelain="$(git -C "$root" status --porcelain 2>/dev/null)"
    # Nothing to hand over while only tmp/ has moved: the task's own folder lives there,
    # so writing the journal would otherwise look like work on the deliverables. The
    # matching below still sees those lines, because a deliverable inside tmp/ is a
    # deliverable.
    [ -n "$(printf '%s' "$porcelain" | grep -vE '^\?\? tmp/' | head -1)" ] || return 0
    local changed; changed="$(printf '%s' "$porcelain" | sed -E 's/^.{3}//')"
    [ -n "$changed" ] || return 0
    local untouched="" path entry touched
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        # Two shapes of entry, and the second one is why comparing strings was wrong: git
        # collapses a wholly untracked directory into one line ending in `/`, so a brand
        # new `skills/thing/SKILL.md` appears only as `skills/thing/`.
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
$(declared_deliverables "$task/spec.md")
EOF
    [ -n "$untouched" ] && finding "The spec of $name declares deliverables that the working tree does not show as touched: $untouched. Work is not done while a declared deliverable is untouched."
    return 0
}

check_spec_drift() {
    local task="$1" at mtime
    [ -f "$task/spec.md" ] || return 0
    at="$(approved_at "$task" spec)"
    if [ "$at" -eq 0 ]; then
        [ -f "$task/plan.md" ] &&
            finding "plan.md exists but spec.md carries no approval in .approvals. The plan is the second approval, not the first."
        return 0
    fi
    mtime="$(stat -c %Y "$task/spec.md" 2>/dev/null || printf 0)"
    [ "$mtime" -gt "$at" ] &&
        finding "spec.md was edited after it was approved ($(date -d "@$at" '+%Y-%m-%d %H:%M:%S') vs $(date -d "@$mtime" '+%Y-%m-%d %H:%M:%S')). A spec edited to match what was built is a report. Either revert the edit or put the new scope to the owner and record it: task.sh approve spec."
    return 0
}

check_status() {
    local task="$1" doc state
    for doc in spec.md plan.md; do
        [ -f "$task/$doc" ] || continue
        state="$(status_state "$task/$doc")"
        case "$task" in
            */tmp/archive/*)
                [ "$state" = done ] ||
                    finding "$doc of an archived task says '$state'. A closed thing carries its end state, and nothing else reads that line into being true."
                ;;
            *)
                if [ "$(approved_at "$task" "${doc%.md}")" -gt 0 ] && [ "$state" = draft ]; then
                    finding "$doc is approved in .approvals but its status line still says draft."
                elif [ "$state" = unknown ]; then
                    finding "$doc has a status line that reads as none of draft, approved or done. Those three words are what a check can act on; the rest of the line is free text."
                fi
                ;;
        esac
    done
    return 0
}

check_template_line() {
    local task="$1" f
    for f in "$task"/*.md; do
        [ -f "$f" ] || continue
        head -1 "$f" | grep -qE '^\*(\[English\]|English )' &&
            finding "$(basename "$f") starts with the template's language switch. That line points at the other copy of the template, not at a translation of this file."
    done
    return 0
}

# Handover only. Mid-task an open checkbox is the normal state, and a check that fires on
# every Stop for it is a check nobody reads by the third day.
check_open_items() {
    local task="$1" open crit
    if [ -f "$task/tasks.md" ]; then
        open="$(grep -cE '^[[:space:]]*- \[ \]' "$task/tasks.md" || true)"
        [ "${open:-0}" -gt 0 ] &&
            finding "tasks.md has $open item(s) still open. Each one is either done, or dropped with its reason in the journal."
    elif [ -f "$task/plan.md" ] && [ "$(approved_at "$task" plan)" -gt 0 ]; then
        finding "the plan is approved but there is no tasks.md. Create it with: task.sh new --tasks"
    fi
    if [ ! -f "$task/spec.md" ]; then
        finding "there is no spec.md, so nothing declared deliverables or acceptance and neither was checked. If that was the owner's call, it stays their call; it is named here so that it is not mistaken for a clean bill."
    else
        crit="$(awk '
            /^#+[[:space:]]*(Acceptance|Приёмка)/ { inside = 1; next }
            /^#+[[:space:]]/ { inside = 0 }
            inside && /^[[:space:]]*[-*][[:space:]]/ { n++ }
            END { printf "%d", n + 0 }
        ' "$task/spec.md")"
        # Counted, never judged: whether a criterion is met is the owner's call, and a
        # script that ticked them off would be the fastest way to lose the acceptance
        # step altogether.
        [ "$crit" -gt 0 ] && NOTE="$crit acceptance criterion(a) in spec.md, each closed by the owner rather than by this script."
    fi
    return 0
}

cmd_check() {
    local given="" quiet="" handover="" arg
    while [ $# -gt 0 ]; do
        arg="$1"; shift
        case "$arg" in
            --quiet)    quiet=1 ;;
            --handover) handover=1 ;;
            -*)         usage ;;
            *)          [ -z "$given" ] && given="$arg" || usage ;;
        esac
    done
    local task; task="$(resolve_task "$given")" || exit 1
    local name; name="$(basename "$task")"
    local root; root="$(repo_root "$task")"

    check_spec_drift "$task"
    [ -n "$root" ] && check_deliverables "$task" "$root" "$name"
    check_status "$task"
    check_template_line "$task"
    [ -n "$handover" ] && check_open_items "$task"

    if [ -z "$FINDINGS" ]; then
        [ -n "$quiet" ] || printf '%s: nothing to report\n' "$name"
        [ -n "$quiet" ] || [ -z "$NOTE" ] || printf '%s\n' "$NOTE"
        return 0
    fi
    printf '%s\n' "$FINDINGS"
    [ -n "$quiet" ] || [ -z "$NOTE" ] || printf '%s\n' "$NOTE"
    return 1
}

# ------------------------------------------------------------------

[ $# -gt 0 ] || usage
sub="$1"; shift
case "$sub" in
    new)     cmd_new "$@" ;;
    approve) cmd_approve "$@" ;;
    check)   cmd_check "$@" ;;
    -h|--help) usage ;;
    *)       usage ;;
esac
