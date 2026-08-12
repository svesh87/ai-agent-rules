#!/usr/bin/env bash
# PostToolUse on a shell command: remember that gates ran in this session.
#
# Exists only so hooks/stop-gates.sh can tell "the tests were run" from "the tests
# were meant to be run". Cheap, silent, and never in the way: it writes one marker
# file into the cache and says nothing to anyone.

set -u
HOOK_NAME="note-gates"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"

hook_read_payload
hook_is_shell_tool || hook_allow

CMD="$(hook_command)"
[ -n "$CMD" ] || hook_allow

# The usual invocations. A project with its own name for the gates is covered by the
# generic ones (make, cargo, ctest) often enough, and a miss only costs a reminder.
printf '%s' "$CMD" | grep -qE '(^|[;&|]\s*)(make\s+(test|check|lint|coverage)|cargo\s+(test|clippy)|ctest|pytest|go\s+test|npm\s+(test|run\s+(test|lint))|npx\s+(vitest|jest|tsc|eslint)|ruff|shellcheck|mypy|golangci-lint|tox|bats)' || hook_allow

sid="$(hook_session_id)"
[ -n "$sid" ] || hook_allow
mkdir -p "$HOOK_CACHE_DIR/session" 2>/dev/null && : > "$HOOK_CACHE_DIR/session/$sid.gates" 2>/dev/null
exit 0
