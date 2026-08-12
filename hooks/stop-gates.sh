#!/usr/bin/env bash
# Stop: before the turn ends, check what the canon says must be checked.
#
# Two things only, both cheap and both easy to forget after a long session.
#
# `git diff --check` catches whitespace damage and conflict markers. It is in the
# canon as part of every handover and it costs milliseconds.
#
# The second is a reminder, not a verdict: if the work tree changed and no test or
# lint command ran in this session, say so. The hook cannot know a project's gates,
# and inventing them would be worse than asking, so it only points.
#
# This hook never blocks. A Stop hook that refuses to let a turn end turns a warning
# into a trap, and the operator, not the hook, decides when work is finished.

set -u
HOOK_NAME="stop-gates"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"

hook_read_payload

CWD="$(hook_cwd)"
repo_context "$CWD" "$(hook_session_id)"
[ -n "${REPO_ROOT:-}" ] || hook_allow

MSG=""

check="$(git -C "$REPO_ROOT" diff --check 2>/dev/null || true)"
if [ -n "$check" ]; then
    MSG="git diff --check is not clean:
$(printf '%s' "$check" | head -5)"
fi

# Did anything change at all?
dirty="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -vE '^\?\? tmp/' | head -1 || true)"
if [ -n "$dirty" ] && policy_allow gates "${REPO_CATEGORY:-none}" "${RULES_MINE:-na}"; then
    marker="$HOOK_CACHE_DIR/session/$(hook_session_id).gates"
    if [ ! -f "$marker" ]; then
        MSG="${MSG:+$MSG
}The work tree changed and no test or lint command ran in this session. Before handing over: run this project's gates, then the consistency pass."
    fi
fi

[ -n "$MSG" ] || hook_allow
hook_warn "$MSG"
exit 0
