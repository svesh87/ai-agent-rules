#!/usr/bin/env bash
# PostToolUse on a document: the marks of machine-generated text.
#
# The canon asks the agent to check its own text before handing it over. Checking your
# own prose is exactly the kind of promise that survives two paragraphs and then
# quietly stops happening, so a grep does it instead.
#
# Code fences and backtick spans are stripped before checking, and that is not a
# convenience: the rules file has to quote the very markers it bans, and so does the
# documentation about this hook. With the examples in backticks the rule stops
# violating itself, and no exception list is needed.
#
# Warning only, never a block. This is a matter of taste with false positives in it,
# and an em dash is sometimes the right punctuation mark.

set -u
HOOK_NAME="prose-check"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"

hook_read_payload
hook_is_edit_tool || hook_allow

TARGET="$(hook_path)"
case "$TARGET" in
    *.md|*.markdown|*.txt) : ;;
    *) hook_allow ;;
esac
[ -f "$TARGET" ] || hook_allow

# Strip fenced blocks, then inline backtick spans, then indented code.
STRIPPED="$(awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    fence { next }
    /^\t|^    [^ *0-9-]/ { next }
    { print }
' "$TARGET" 2>/dev/null | sed 's/`[^`]*`//g')"
[ -n "$STRIPPED" ] || hook_allow

FOUND=""
note() { FOUND="${FOUND:+$FOUND
}$1"; }

hits() { printf '%s' "$STRIPPED" | grep -icE "$1" 2>/dev/null || printf 0; }

n="$(hits '—')"
[ "$n" -gt 0 ] 2>/dev/null && note "$n line(s) with an em dash: use a comma or a colon unless the dash is genuinely the right mark"

n="$(hits 'not just [^,]+, but |не просто [^,]+, а ')"
[ "$n" -gt 0 ] 2>/dev/null && note "$n line(s) with the \"not just X, but Y\" construction"

n="$(hits 'it is important to note|important to note that|in conclusion|great question|в заключение|стоит отметить, что|важно отметить')"
[ "$n" -gt 0 ] 2>/dev/null && note "$n line(s) with filler phrasing that adds nothing"

n="$(hits '\b(delve|leverage|robust|seamless|deep dive|game.changer|unlock the power)\b')"
[ "$n" -gt 0 ] 2>/dev/null && note "$n line(s) with marketing vocabulary"

n="$(printf '%s' "$STRIPPED" | grep -cE '^#+ .*[😀-🿿🚀-🛿☀-⛿✀-➿]' 2>/dev/null || printf 0)"
[ "$n" -gt 0 ] 2>/dev/null && note "$n heading(s) with an emoji"

[ -n "$FOUND" ] || hook_allow

hook_warn "$(printf 'Prose check on %s:\n%s\nFix it now rather than at handover.' "$TARGET" "$FOUND")"
exit 0
