#!/usr/bin/env bash
# PreToolUse: a file in the work tree is edited with an editor, not with the shell.
#
# This is the rule that fails most often, and by a wide margin. Measured over three
# days of transcripts: 750 edits made by piping a file through a script against 452
# made with the editor. The share grows from 4% in the first sixth of a session to
# 97% by the middle, and it breaks well before the first context compaction, so the
# cause is dilution of the instruction, not compaction. Text cannot hold this rule.
# A hook can: it does not get tired five hours in.
#
# Why it matters at all: a change made through the shell does not show up as a diff
# the operator can review, and a replace() against a file whose content shifted
# silently edits the wrong thing.
#
# Editing with Edit or Write is never blocked, anywhere. That is deliberate: the way
# to fix a broken hook must stay open by construction, not by luck.

set -u
HOOK_NAME="guard-shell-edit"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"

hook_read_payload
hook_is_shell_tool || hook_allow

CMD="$(hook_command)"
[ -n "$CMD" ] || hook_allow

# The grants directory is written by guard-write-scope.sh out of the owner's own words
# in the harness — the rejection dialog in Claude Code, the next chat message in Codex —
# and never by a command: a shell write toward it is a way to mint
# permission, so it is refused, and this sits above the scratch exemption on purpose —
# a cache resolved into scratch space must not turn the tripwire off. Reading a grant,
# or rm to revoke one, stays out of the pattern: the failure direction of a lost grant
# is a question to the owner, not an allow.
if printf '%s' "$CMD" | grep -q 'agent-rules/grants' &&
   printf '%s' "$CMD" | grep -qE '((^|[^0-9])>|\btee\b|\bcp\b|\bmv\b|\btouch\b|\bmkdir\b|\bln\b|\bdd\b|\bsed\b|\bawk\b|\bperl\b|\bpython3?\b)'; then
    # The redirect pattern skips a digit before the `>`: `2>/dev/null` on an rm that
    # revokes a grant is not a write toward the directory, and revocation must stay free.
    hook_deny "Blocked: grants under agent-rules/grants/ are created from the owner's own words typed into the harness, not by commands."
fi

# Scratch space is exempt: generating a file with a script is legitimate work, and
# nothing under tmp/ or the system temporary directory is ever reviewed as a diff.
#
# The `tmp/` prefixes cover the whole layout under it — work/, ideas/, archive/, old/ —
# because the match is on the directory and not on what follows it. `tmp/old/` is kept
# as its own pattern only for a command that names it without a separator in front.
case "$CMD" in
    *" tmp/"*|*"/tmp/"*|*"tmp/old/"*) hook_allow ;;
esac

# Extensions worth protecting: source, configuration and prose that lands in git.
EXT='md|rs|py|sh|bash|c|h|cpp|hpp|cc|go|js|ts|tsx|jsx|json|toml|yaml|yml|ini|cfg|sql|tf|rb|php|java|kt|swift|vue|css|scss|html'

reason=""

# A script that reads a file, replaces inside it and writes it back. The pair of
# markers matters: reading a file to print or grep it is fine.
if printf '%s' "$CMD" | grep -qE '(read_text\(\)|\.read\(\)|readFileSync|file_get_contents)' &&
   printf '%s' "$CMD" | grep -qE '(\.replace\(|\.sub\(|re\.sub|write_text\(|\.write\(|writeFileSync|file_put_contents)'; then
    reason="a script that rewrites a file in place"
fi

# In-place stream editors.
if [ -z "$reason" ] && printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*|\s)(sed|perl|gawk|awk)\s+[^|;&]*-i'; then
    reason="in-place stream edit"
fi

# Redirection and tee onto a tracked-looking file.
if [ -z "$reason" ] && printf '%s' "$CMD" | grep -qE "(>|>>|\|\s*tee(\s+-a)?)\s+[^ ;&|]*\.($EXT)(\s|$|;|&|\|)"; then
    reason="shell redirection onto a source or document file"
fi

[ -n "$reason" ] || hook_allow

hook_deny "$(cat <<EOF
Blocked: $reason. Use Edit or Write instead, so the change is reviewable as a diff.
Generating files under tmp/ or /tmp with a script is fine and is not blocked.
If this really is the exception, say so and the operator decides.
EOF
)"
