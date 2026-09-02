#!/usr/bin/env bash
# Rebuild a journal skeleton out of a session transcript, after the context was lost.
#
# This is the floor, not a substitute. A transcript holds what was done — which files
# were edited, which commands ran — and almost nothing of why: the rejected approach,
# the number a measurement produced, the trap found. Those live in journal.md because
# they cannot be recovered from anywhere else. What this script recovers is the
# scaffolding, so that reconstructing the rest is a review rather than an excavation.
#
# It writes nothing on its own. The skeleton goes to stdout and the person running it
# decides what belongs in the journal.
#
# Usage:
#   scripts/journal-from-transcript.sh <transcript.jsonl> [> skeleton.md]
#   scripts/journal-from-transcript.sh --latest   # newest transcript for this directory
#
# Claude Code keeps transcripts as JSON Lines under
# ~/.claude/projects/<slug>/<session>.jsonl. A Codex payload declares `transcript_path`
# but the observed value was empty, so there this script has nothing to read; that is a
# property of the harness and is recorded in docs/mechanisms.md.

set -u

if ! command -v jq >/dev/null 2>&1; then
    printf 'jq is required to read a transcript\n' >&2
    exit 1
fi

FILE="${1:-}"
if [ "$FILE" = "--latest" ] || [ -z "$FILE" ]; then
    # The slug is the working directory with the separators replaced, which is an
    # undocumented detail of the harness. So the newest transcript under any project
    # directory whose slug contains this directory's basename is taken, and the file
    # actually used is printed: guessing silently would be worse than guessing loudly.
    base="$(basename "$PWD")"
    FILE="$(find "${HOME}/.claude/projects" -name '*.jsonl' -path "*${base}*" \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
    [ -n "$FILE" ] || { printf 'no transcript found for %s\n' "$PWD" >&2; exit 1; }
    printf 'reading %s\n\n' "$FILE" >&2
fi

[ -f "$FILE" ] || { printf 'not a file: %s\n' "$FILE" >&2; exit 1; }

printf '## Recovered from the transcript\n\n'
printf 'Scaffolding only, pulled out of `%s`.\n' "$(basename "$FILE")"
printf 'What was done, never why. Fill in the reasons before this becomes a journal entry.\n\n'

printf '### Files edited\n\n'
jq -r '
    .. | objects
    | select(.type? == "tool_use")
    | select(.name? == "Edit" or .name? == "Write" or .name? == "MultiEdit" or .name? == "NotebookEdit")
    | .input.file_path // .input.path // .input.notebook_path // empty
' "$FILE" 2>/dev/null | sed 's|^'"$PWD"'/||' | sort | uniq -c | sort -rn |
    awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "- `%s` (%d edit%s)\n", $0, n, (n == 1 ? "" : "s") }'
printf '\n'

printf '### Commands run\n\n'
printf 'Deduplicated and in order of first appearance. Gates and probes are the ones\n'
printf 'worth keeping; the rest is noise from reading the repository.\n\n'
jq -r '
    .. | objects
    | select(.type? == "tool_use")
    | select(.name? == "Bash" or .name? == "shell")
    | (.input.command // .input.script // empty)
    | split("\n")[0]
' "$FILE" 2>/dev/null | awk '!seen[$0]++ { print "- `" $0 "`" }'
printf '\n'

printf '### What is missing and has to come from memory\n\n'
printf -- '- approaches that were tried and rejected, and why\n'
printf -- '- what each measurement showed, with its number\n'
printf -- '- traps found that will bite the next person\n'
printf -- '- decisions taken in chat that never reached a file\n'
