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

set -u
HOOK_NAME="guard-write-scope"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"

hook_read_payload
hook_is_edit_tool || hook_allow

TARGET="$(hook_path)"
[ -n "$TARGET" ] || hook_allow

CWD="$(hook_cwd)"
case "$TARGET" in
    /*) ABS="$TARGET" ;;
    *)  ABS="$CWD/$TARGET" ;;
esac

repo_context "$CWD" "$(hook_session_id)"
ROOT="${REPO_ROOT:-$CWD}"

# Both paths are resolved before anything is compared, and that is the whole difference
# between a boundary and the appearance of one. Comparing the strings let four shapes
# through: a symlink pointing out of the tree in either form, `../` into the repository
# next door, and enough `../` to reach the home directory. The last one is the clearest,
# because the same file was refused when named absolutely and allowed when named with two
# dots. A symlink was never needed to get out, only the dots, so this was never about one
# machine's layout.
#
# -m resolves a path whose last component does not exist yet, which is the normal case for
# a file about to be written. A missing realpath means a machine without coreutils, and the
# rule for that is the same as everywhere in these hooks: allow, and say so in the log. A
# realpath that runs and fails on this particular path is the opposite case, because an
# unresolvable path is exactly what is being guarded against, so it goes to the owner.
if command -v realpath >/dev/null 2>&1; then
    ABS_R="$(realpath -m "$ABS" 2>/dev/null)" || ABS_R=""
    ROOT_R="$(realpath -m "$ROOT" 2>/dev/null)" || ROOT_R=""
    if [ -z "$ABS_R" ] || [ -z "$ROOT_R" ]; then
        hook_ask "$ABS does not resolve to a path that can be checked against this work tree ($ROOT). Confirm only if this is the path the owner named."
    fi
    ABS="$ABS_R"
    ROOT="$ROOT_R"
else
    hook_log "realpath is absent, comparing paths as written"
fi

# Our own files in a foreign checkout, and only ours.
#
# This sits above the in-tree allow on purpose: the paths it is about are inside the tree,
# and below that line it was unreachable, which is how the rule about not furnishing someone
# else's repository turned out never to have been enforced at all.
#
# Narrow by name rather than by direction. An edit to their code may be exactly what the
# owner asked for, and asking about every file in a foreign repository would make working on
# an upstream project a stream of questions. What does not belong there is our tooling: the
# rules files and the two agent directories. `tmp/` is deliberately not in the list, since
# the machine-wide ignore covers it and it never reaches their git.
if [ -n "${REPO_CATEGORY:-}" ] && ! policy_allow tree-footprint "$REPO_CATEGORY" "${RULES_MINE:-na}"; then
    case "$ABS" in
        "$ROOT"/*)
            case "${ABS#"$ROOT"/}" in
                AGENTS.md|*/AGENTS.md|CLAUDE.md|*/CLAUDE.md|*.local.md|.claude/*|*/.claude/*|.codex/*|*/.codex/*)
                    hook_ask "This leaves one of our own files in a foreign checkout ($REPO_CATEGORY): ${ABS#"$ROOT"/}. Their repository keeps none of our tooling; tmp/ or the machine's own configuration is where this goes. Confirm only if this is what the owner asked for." ;;
            esac ;;
    esac
fi

# Inside the work tree: always allowed.
case "$ABS" in
    "$ROOT"/*) hook_allow ;;
esac

# Scratch space outside the tree: allowed, that is what it is for.
case "$ABS" in
    /tmp/*|"${TMPDIR:-/nonexistent}"/*) hook_allow ;;
esac

# The agent's own memory: allowed, because it is not the operator's file.
#
# The harness keeps a session's memory in `~/.claude/projects/<slug>/memory/`, and every
# write there landed on the ask below. The log has the evidence across four projects, always
# the same two files, `MEMORY.md` and one note beside it. At the keyboard that costs a
# confirmation; with nobody at the keyboard, which is a subagent or a session left to run,
# there is nothing to answer the question with and the write stalls mid-task.
#
# The rule this exempts is about the operator's files, and memory is not one: the agent
# created it, nothing else reads it, and it is outside every repository by the harness's
# design rather than by an agent wandering off. The whole `projects/*/memory/` tree goes in,
# not the slug for this directory alone, because that slug is an undocumented detail of the
# harness — a dot in a path, a worktree or a session opened in a subdirectory all change it,
# and a near miss brings the stall back.
#
# Deliberately narrower than the directory above it. `projects/<slug>/` also holds the
# transcripts and the todo state, which the agent has no business editing, so the exemption
# stops at `memory/`.
#
# Codex keeps its memory in one directory for the whole machine, and there the same width
# would be wrong. `~/.codex/memories/` is a git repository holding the consolidated memory,
# its summaries and the rollout summaries, all of which the harness writes for itself. What
# an agent writes on request is a note under `extensions/ad_hoc/notes/`, so that is all that
# is exempt; the name is not taken on trust, it is the path in the `codex` binary. Its
# `instructions.md` next door stays behind the ask, because that file is the extension's own
# configuration rather than a note.
#
# CODEX_HOME moves that directory, and install.sh already honours it, so this reads the same
# variable rather than assuming `~/.codex`.
#
# The bases are resolved for the same reason ABS is: a comparison between a resolved path and
# an unresolved pattern is a string comparison wearing a boundary's clothes, and a home
# directory reached through a symlink would miss and stall.
#
# All of it sits after the paths are resolved, which is what keeps it from becoming a way
# out: a symlink or a `..` inside either directory that leads anywhere else no longer matches
# the pattern by the time these lines run, and falls through to the ask.
MEM_CLAUDE="${HOME:-/nonexistent}/.claude/projects"
MEM_CODEX="${CODEX_HOME:-${HOME:-/nonexistent}/.codex}/memories/extensions/ad_hoc/notes"
if command -v realpath >/dev/null 2>&1; then
    MEM_CLAUDE="$(realpath -m "$MEM_CLAUDE" 2>/dev/null || printf '%s' "$MEM_CLAUDE")"
    MEM_CODEX="$(realpath -m "$MEM_CODEX" 2>/dev/null || printf '%s' "$MEM_CODEX")"
fi
case "$ABS" in
    "$MEM_CLAUDE"/*/memory/*) hook_allow ;;
    "$MEM_CODEX"/*) hook_allow ;;
esac

# Everything else is outside the work tree: the operator's own files, another
# repository, the home directory. Opened on request, at the named path, one act at a
# time.
hook_ask "$(cat <<EOF
$ABS is outside this work tree ($ROOT).
Files outside the repository are opened only at the owner's request and only at the
path they name; reading is the default, writing needs a request of its own.
Confirm if this is the path they named, otherwise refuse and say so.
EOF
)"
