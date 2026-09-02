#!/usr/bin/env bash
# PreToolUse: where an editing tool is allowed to write.
#
# Two rules, both [hard] in the canon. The operator's own files are read-only to an
# agent: it writes what it created and what it was handed. And a foreign checkout keeps
# none of our tooling, because leaving it there is a change to someone else's tree that
# nobody asked for.
#
# Our tooling, not every file. Their own code is theirs, and an edit to it is often the
# work itself, so the second rule is enforced by name: the rules files and the two agent
# directories. A draft under their `tmp/` is left alone, since the machine-wide ignore
# covers it and it never reaches their git.
#
# An ordinary path inside the current work tree is never stopped. That is the property
# that keeps a broken hook fixable, and it is not negotiable: everything this hook stops is
# a path outside the tree, or one of our own files being left in a tree that is not ours.
#
# Stopped, not refused. Both cases here are exactly the ones the canon settles by asking
# the owner, so they go out as an ask decision and the harness puts the question. Measured
# on this machine in permission mode `auto`: the question reached the owner, an approval
# let the write through and a refusal stopped it with the reason coming back. Where ask is
# unavailable, hook_ask refuses with the same text rather than guessing.
#
# The ask can also be answered for a while, not only per file. A session working across a
# neighbouring repository used to cost the owner one click per write; now the owner types
# «на 10 минут» or «на час» into the rejection dialog instead of clicking Yes, and the
# retry finds those words in the transcript — inside the wrapper the harness writes, which
# an agent cannot forge — and creates a time-boxed grant for that repository
# (lib/grants.sh). Only this ask honours grants: the branch about our files in a foreign
# tree stays per-file, and so does everything in guard-destructive.sh, because permission
# to write is not consent to everything.
#
# Outside Claude Code there is no dialog to answer: Codex rejects an ask decision as
# unsupported and marks the hook failed, which makes it drop our verdict, so the refusal
# below is the only shape that holds. The scope of that refusal is recorded either way
# (grant_asked_record), and in Codex the owner answers it with the next chat message,
# which hooks/prompt-nudge.sh turns into the same kind of grant. The sentence addressed to
# the owner therefore differs by tool, further down.
#
# One path skips the ask outright rather than being granted for a while: `tmp/TODO.md` at
# the root of another repository of ours, the intake tray. "Put this in that repo's TODO"
# is a request the owner makes and then leaves the window, so a confirmation there waits
# for somebody who is not coming back. The branch itself carries how narrow it is.
#
# One call, several paths. This used to read one field, `tool_input.file_path`, and allow
# the call when it came back empty — which is every `apply_patch` in Codex, where the
# whole patch arrives in `tool_input.command` instead. A probe wrote a file outside every
# work tree, silently, and left nothing in the hook log. So the paths now come from
# hook_paths, every one of them is judged, and a call whose paths cannot be read is
# stopped rather than waved through.

set -u
HOOK_NAME="guard-write-scope"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"
# shellcheck source=../lib/grants.sh
. "$HERE/../lib/grants.sh"

hook_read_payload
hook_is_edit_tool || hook_allow

CWD="$(hook_cwd)"
repo_context "$CWD" "$(hook_session_id)"
ROOT="${REPO_ROOT:-$CWD}"
PATHS="$(hook_paths)"

VERDICT_ASK=""
VERDICT_DECIDE=""

# judge_path <path> — 0 to allow silently, 1 to ask with the reason in VERDICT_ASK,
# 3 to allow with an explicit decision whose reason is in VERDICT_DECIDE.
#
# Everything it needs is local, because it runs once per path in the call and a value
# left over from the previous path would judge the next one.
judge_path() {
    local TARGET="$1" ABS ROOT="$ROOT"
    local ABS_R ROOT_R MEM_CLAUDE MEM_CODEX
    local tray_root tray_top tray_cat
    local GRANT_SCOPE GRANT_HIT SID TRANSCRIPT HOW_TO_GRANT
    local asked_scope asked_at fb fb_ts fb_text asked_iso mins

    case "$TARGET" in
        /*) ABS="$TARGET" ;;
        *)  ABS="$CWD/$TARGET" ;;
    esac

    # Both paths are resolved before anything is compared, and that is the whole
    # difference between a boundary and the appearance of one. Comparing the strings let
    # four shapes through: a symlink pointing out of the tree in either form, `../` into
    # the repository next door, and enough `../` to reach the home directory. The last
    # one is the clearest, because the same file was refused when named absolutely and
    # allowed when named with two dots. A symlink was never needed to get out, only the
    # dots, so this was never about one machine's layout.
    #
    # -m resolves a path whose last component does not exist yet, which is the normal
    # case for a file about to be written. A missing realpath means a machine without
    # coreutils, and the rule for that is the same as everywhere in these hooks: allow,
    # and say so in the log. A realpath that runs and fails on this particular path is
    # the opposite case, because an unresolvable path is exactly what is being guarded
    # against, so it goes to the owner.
    if command -v realpath >/dev/null 2>&1; then
        ABS_R="$(realpath -m "$ABS" 2>/dev/null)" || ABS_R=""
        ROOT_R="$(realpath -m "$ROOT" 2>/dev/null)" || ROOT_R=""
        if [ -z "$ABS_R" ] || [ -z "$ROOT_R" ]; then
            VERDICT_ASK="$ABS does not resolve to a path that can be checked against this work tree ($ROOT). Confirm only if this is the path the owner named."
            return 1
        fi
        ABS="$ABS_R"
        ROOT="$ROOT_R"
    else
        hook_log "realpath is absent, comparing paths as written"
    fi

    # Our own files in a foreign checkout, and only ours.
    #
    # This sits above the in-tree allow on purpose: the paths it is about are inside the
    # tree, and below that line it was unreachable, which is how the rule about not
    # furnishing someone else's repository turned out never to have been enforced at all.
    #
    # Narrow by name rather than by direction. An edit to their code may be exactly what
    # the owner asked for, and asking about every file in a foreign repository would make
    # working on an upstream project a stream of questions. What does not belong there is
    # our tooling: the rules files and the two agent directories. `tmp/` is deliberately
    # not in the list, since the machine-wide ignore covers it and it never reaches their
    # git.
    if [ -n "${REPO_CATEGORY:-}" ] && ! policy_allow tree-footprint "$REPO_CATEGORY" "${RULES_MINE:-na}"; then
        case "$ABS" in
            "$ROOT"/*)
                case "${ABS#"$ROOT"/}" in
                    AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|*.local.md|.claude/*|*/.claude/*|.codex/*|*/.codex/*)
                        VERDICT_ASK="This leaves one of our own files in a foreign checkout ($REPO_CATEGORY): ${ABS#"$ROOT"/}. Their repository keeps none of our tooling; tmp/ or the machine's own configuration is where this goes. Confirm only if this is what the owner asked for."
                        return 1 ;;
                esac ;;
        esac
    fi

    # Inside the work tree: always allowed.
    case "$ABS" in
        "$ROOT"/*) return 0 ;;
    esac

    # Scratch space outside the tree: allowed, that is what it is for.
    case "$ABS" in
        /tmp/*|"${TMPDIR:-/nonexistent}"/*) return 0 ;;
    esac

    # The agent's own memory: allowed, because it is not the operator's file.
    #
    # The harness keeps a session's memory in `~/.claude/projects/<slug>/memory/`, and
    # every write there landed on the ask below. The log has the evidence across four
    # projects, always the same two files, `MEMORY.md` and one note beside it. At the
    # keyboard that costs a confirmation; with nobody at the keyboard, which is a
    # subagent or a session left to run, there is nothing to answer the question with and
    # the write stalls mid-task.
    #
    # The rule this exempts is about the operator's files, and memory is not one: the
    # agent created it, nothing else reads it, and it is outside every repository by the
    # harness's design rather than by an agent wandering off. The whole
    # `projects/*/memory/` tree goes in, not the slug for this directory alone, because
    # that slug is an undocumented detail of the harness — a dot in a path, a worktree or
    # a session opened in a subdirectory all change it, and a near miss brings the stall
    # back.
    #
    # Deliberately narrower than the directory above it. `projects/<slug>/` also holds
    # the transcripts and the todo state, which the agent has no business editing, so the
    # exemption stops at `memory/`.
    #
    # Codex keeps its memory in one directory for the whole machine, and there the same
    # width would be wrong. `~/.codex/memories/` is a git repository holding the
    # consolidated memory, its summaries and the rollout summaries, all of which the
    # harness writes for itself. What an agent writes on request is a note under
    # `extensions/ad_hoc/notes/`, so that is all that is exempt; the name is not taken on
    # trust, it is the path in the `codex` binary. Its `instructions.md` next door stays
    # behind the ask, because that file is the extension's own configuration rather than
    # a note.
    #
    # CODEX_HOME moves that directory, and install.sh already honours it, so this reads
    # the same variable rather than assuming `~/.codex`.
    #
    # The bases are resolved for the same reason ABS is: a comparison between a resolved
    # path and an unresolved pattern is a string comparison wearing a boundary's clothes,
    # and a home directory reached through a symlink would miss and stall.
    #
    # All of it sits after the paths are resolved, which is what keeps it from becoming a
    # way out: a symlink or a `..` inside either directory that leads anywhere else no
    # longer matches the pattern by the time these lines run, and falls through to the ask.
    MEM_CLAUDE="${HOME:-/nonexistent}/.claude/projects"
    MEM_CODEX="${CODEX_HOME:-${HOME:-/nonexistent}/.codex}/memories/extensions/ad_hoc/notes"
    if command -v realpath >/dev/null 2>&1; then
        MEM_CLAUDE="$(realpath -m "$MEM_CLAUDE" 2>/dev/null || printf '%s' "$MEM_CLAUDE")"
        MEM_CODEX="$(realpath -m "$MEM_CODEX" 2>/dev/null || printf '%s' "$MEM_CODEX")"
    fi
    case "$ABS" in
        "$MEM_CLAUDE"/*/memory/*) return 0 ;;
        "$MEM_CODEX"/*) return 0 ;;
    esac

    # The intake tray of another repository of ours: allowed, without a question, always.
    #
    # The use it exists for is one sentence long — "put this in the TODO of that repo" —
    # and the owner types it and walks away. Behind an ask that request stalls until they
    # come back to a window they have already left, which is the worst possible place for
    # a confirmation: nothing is at stake and nobody is there.
    #
    # The hole is kept the size of the use. One filename, in one directory, one level
    # below a git root, resolved before it is judged: a symlink or a `..` that leads
    # anywhere else has stopped matching by the time this runs. The category is classified
    # for the target repository rather than the session's, so a foreign checkout still
    # asks — the rule that their tree keeps none of our files is not weakened by a
    # convenience of ours. `tmp/` is covered by the machine-wide ignore, so nothing here
    # can reach anyone's git. Deleting or moving the same file is untouched by this and
    # stays with guard-destructive.sh: a line appended is not the same act as a tray
    # thrown away.
    case "$ABS" in
        */tmp/TODO.md)
            tray_root="${ABS%/tmp/TODO.md}"
            tray_top="$(git -C "$tray_root" rev-parse --show-toplevel 2>/dev/null || printf '')"
            if [ -n "$tray_top" ] && command -v realpath >/dev/null 2>&1; then
                tray_top="$(realpath -m "$tray_top" 2>/dev/null || printf '%s' "$tray_top")"
            fi
            if [ -n "$tray_top" ] && [ "$tray_top" = "$tray_root" ]; then
                # In a subshell: repo_classify sets the REPO_* variables, and the branches
                # above still speak about the repository the session is in.
                tray_cat="$( (repo_classify "$tray_root" >/dev/null 2>&1
                              printf '%s %s' "${REPO_CATEGORY:-}" "${RULES_MINE:-na}") )"
                # shellcheck disable=SC2086
                if policy_allow tree-footprint ${tray_cat:-none na}; then
                    VERDICT_DECIDE="The intake tray of $tray_root, which is ours; appending to it needs no question."
                    return 3
                fi
            fi ;;
    esac

    # Everything else is outside the work tree: the operator's own files, another
    # repository, the home directory. Opened on request, at the named path, one act at a
    # time — or for a granted while, when the owner said so in the rejection dialog.
    GRANT_SCOPE="$(grant_scope_of "$ABS")"

    if GRANT_HIT="$(grant_match "$ABS")"; then
        VERDICT_DECIDE="A live write grant from the owner covers $GRANT_HIT."
        return 3
    fi

    # Did the owner answer the previous ask with a grant phrase instead of a click? The
    # phrase is read out of the transcript, not out of the agent's message: the wrapper
    # around it is written by the harness, and the recency checks tie it to our own ask —
    # the same repository, an ask at most ten minutes old, the rejection not older than
    # the ask. Everything that fails to parse falls through to asking again; the failure
    # direction here is never an allow.
    SID="$(hook_session_id)"
    TRANSCRIPT="$(hook_field '.transcript_path')"
    if [ -n "$TRANSCRIPT" ] && asked_scope="$(grant_asked_scope "$SID")" &&
       [ "$asked_scope" = "$GRANT_SCOPE" ]; then
        asked_at="$(grant_asked_at "$SID")" || asked_at=""
        fb="$(grant_rejection_feedback "$TRANSCRIPT")"
        fb_ts="${fb%%$'\t'*}"
        fb_text="${fb#*$'\t'}"
        asked_iso=""
        [ -n "$asked_at" ] && asked_iso="$(date -u -d "@$asked_at" +%Y-%m-%dT%H:%M:%S 2>/dev/null)"
        if [ -n "$fb" ] && [ -n "$asked_iso" ] && ! [ "${fb_ts:0:19}" \< "$asked_iso" ]; then
            if mins="$(grant_phrase_minutes "$fb_text")"; then
                grant_create "$GRANT_SCOPE" "$mins" "owner's phrase in the rejection dialog, session $SID"
                grant_asked_clear "$SID"
                VERDICT_DECIDE="The owner granted writes in $GRANT_SCOPE for $mins minutes."
                return 3
            fi
        fi
    fi

    grant_asked_record "$SID" "$GRANT_SCOPE"

    # The two channels differ, so the sentence addressed to the owner differs. In Claude
    # Code the answer goes in the rejection dialog; in Codex there is no dialog of ours,
    # because its runtime rejects an ask, so the answer is the next chat message.
    if [ -n "${CLAUDECODE:-}" ]; then
        HOW_TO_GRANT="To the owner: Yes allows this one file. To allow writes in $GRANT_SCOPE for a while,
reject with the reason «на 10 минут» or «на час» — the agent then retries this call
and the retry passes without a question."
    else
        HOW_TO_GRANT="To the owner: to allow writes in $GRANT_SCOPE for a while, send «на 10 минут» or
«на час» as your next message, on its own. Nothing else in that message, or it does not
count. The retry then passes this check; Codex may still put its own question."
    fi

    VERDICT_ASK="$(cat <<EOF
$ABS is outside this work tree ($ROOT).
Files outside the repository are opened only at the owner's request and only at the
path they name; reading is the default, writing needs a request of its own.
Confirm if this is the path they named, otherwise refuse and say so.
$HOW_TO_GRANT
EOF
)"
    return 1
}

# An editing call whose paths cannot be worked out is stopped, not waved through. That
# direction is the whole fix: reading one field and allowing when it came back empty is
# how a patch wrote outside every work tree without leaving a trace.
if [ -z "$PATHS" ]; then
    hook_ask "This is an editing call ($(hook_tool)) whose target path cannot be read from the payload, so it cannot be checked against this work tree ($ROOT). Confirm only if the owner named the path; otherwise refuse and say what was attempted."
fi

# The strictest verdict across the paths wins, and an ask ends the walk: there is nothing
# to gain from judging the rest of a patch that is already going to the owner. The loop
# reads from a here-document rather than a pipe, so the verdict variables it sets are the
# ones this shell goes on to read.
rc=0
while IFS= read -r one_path; do
    [ -n "$one_path" ] || continue
    judge_path "$one_path" || rc=$?
    [ "$rc" = 1 ] && break
done <<PATHLIST
$PATHS
PATHLIST

case "$rc" in
    1) hook_ask "$VERDICT_ASK" ;;
    3) hook_allow_decision "$VERDICT_DECIDE" ;;
esac
hook_allow
