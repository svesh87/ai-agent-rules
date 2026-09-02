#!/usr/bin/env bash
# PreToolUse: operations that are hard or impossible to undo, and pushes out of
# repositories that are not ours.
#
# These are the [hard] rules whose cost of failure is not a bad diff but lost work:
# rewritten history, a discarded working tree, an unsigned commit in a repository
# whose policy is to sign, a push into someone else's project.
#
# The hook does not replace asking. It catches the case where the instruction was
# read five hours ago and the command looks routine.
#
# Two of the checks here now put the question instead of refusing, and the split is not
# arbitrary. A recursive delete outside tmp/ and a broad cleanup of services are operations
# the owner does sometimes want, and what was missing was consent for this exact one. An
# unsigned commit, a force push, a rewritten history and a push out of a category that
# forbids it are not in that class: there is no version of them the owner would approve in
# passing, so they stay refusals.
#
# A push is judged by the repository the command runs in, not the one the session sits
# in: `cd <clone> && git push` and `git -C <clone> push` are pushes from the clone. When
# that directory cannot be read out of the command at all, the push becomes a question
# for the owner rather than a verdict either way.

set -u
HOOK_NAME="guard-destructive"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/payload.sh
. "$HERE/../lib/payload.sh"
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
# shellcheck source=../lib/policy.sh
. "$HERE/../lib/policy.sh"

hook_read_payload
hook_is_shell_tool || hook_allow

CMD="$(hook_command)"
[ -n "$CMD" ] || hook_allow

# What the checks below actually read, and why it is not the command as written.
#
# A quoted string is data. A commit message that mentions a force push was being denied,
# and so was a grep whose pattern contained rm -rf: the vertical bar inside such a pattern
# reads as a pipe, which is how a grep came to look like the start of a delete. Measured
# on this machine, three of five harmless commands that merely named an operation were
# blocked.
#
# A quoted string handed to an executor is a command, not data. bash -c, sh -c, eval, ssh
# and sudo sh -c all took a real recursive delete straight past this hook, because rm then
# follows a quote rather than a separator. Same for xargs, which is a separator wearing
# another hat.
#
# So: an executor's payload becomes a segment of its own, xargs becomes a separator, and
# whatever is still quoted afterwards becomes a placeholder. Nesting deeper than one level
# (a quote inside an unwrapped payload) is out of reach here and stays a matter for asking.
executor='(sudo[[:space:]]+)?(eval|(ba|z|k)?sh[[:space:]]+-c|ssh[[:space:]]+[^[:space:]]+|docker[[:space:]]+exec([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^[:space:]]+)'
#
# The payload is \7: two groups for the separator and the space before the executor, four
# inside the executor itself, then the quoted body. A wrong number here is not a small
# mistake, it is sed failing on every command and this hook allowing everything, which is
# why an empty result falls back to the command as written and says so in the log.
SCAN="$(printf '%s' "$CMD" | sed -E \
    -e "s/(^|[;&|])([[:space:]]*)$executor[[:space:]]*\"([^\"]*)\"/\1\2 ; \7 ; /g" \
    -e "s/(^|[;&|])([[:space:]]*)$executor[[:space:]]*'([^']*)'/\1\2 ; \7 ; /g" \
    -e "s/(^|[;&|])([[:space:]]*)xargs([[:space:]]+-[^[:space:]]+)*[[:space:]]+/\1\2 ; /g" \
    -e "s/\"[^\"]*\"/QUOTED/g" \
    -e "s/'[^']*'/QUOTED/g" 2>/dev/null)"
if [ -z "$SCAN" ]; then
    hook_log "the masking pass produced nothing, checking the command as written"
    SCAN="$CMD"
fi

# Signing is the operator's policy, not an obstacle in the way of a commit.
if printf '%s' "$SCAN" | grep -qE '(--no-gpg-sign|-c\s+commit\.gpgsign=false)'; then
    hook_deny "Blocked: signing is switched off. Signing is the owner's policy. If the key times out, retry once and then hand over a ready git commit -F <file>."
fi

# History rewrites and force pushes. The optional -C is part of the anchor: without it
# `git -C <clone> push --force` slid past a check built to stop exactly that.
if printf '%s' "$SCAN" | grep -qE 'git\s+(-C\s+[^[:space:];&|]+\s+)?push[^;&|]*(--force([^-]|$)|-f(\s|$))'; then
    hook_deny "Blocked: force push. --force is never ours to add. Show the discrepancy and let the owner decide."
fi
if printf '%s' "$SCAN" | grep -qE 'git\s+(reset\s+--hard|filter-branch|filter-repo|rebase[^;&|]*-i)'; then
    hook_deny "Blocked: this rewrites history or discards the working tree. Ask for this specific operation first."
fi

# A recursive delete outside scratch space. The target is read back out of the command as
# written when the scan only has the placeholder for it, so that a quoted tmp/ path keeps its
# exemption and the question can still name what it is about.
#
# Recursion is what matters here, and the `f` does not. The pattern used to require both
# letters, so `rm -r build/` walked past a guard built to stop exactly that, and the long
# form `--recursive` was never considered at all. An optional `sudo` is part of the anchor
# for the same reason: without it `sudo rm -rf /opt` failed the "start of a segment" test and
# passed, which was found by watching this hook let one through while writing its own tests.
if printf '%s' "$SCAN" | grep -qE '(^|[;&|]\s*)(sudo\s+)?rm\s+(-[a-zA-Z]*\s+)*(-[a-zA-Z]*[rR]|--recursive)'; then
    target="$(printf '%s' "$SCAN" | grep -oE 'rm\s+(-[a-zA-Z]+\s+)*[^ ;&|]+' | tail -1 | awk '{print $NF}')"
    if [ "$target" = QUOTED ] || [ -z "$target" ]; then
        target="$(printf '%s' "$CMD" | grep -oE 'rm\s+(-[a-zA-Z]+\s+)*[^;&|]+' | tail -1 |
            awk '{print $NF}' | tr -d "\"'")"
    fi
    case "$target" in
        tmp/*|./tmp/*|/tmp/*|*/tmp/*|"${TMPDIR:-/nonexistent}"/*) : ;;
        *) hook_ask "Recursive delete outside tmp/ and /tmp (target: ${target:-unparsed}). This needs approval for this exact path." ;;
    esac
fi

# Broad service and data cleanups.
if printf '%s' "$SCAN" | grep -qE '(docker\s+system\s+prune|docker\s+volume\s+prune|iptables\s+-F|nft\s+flush\s+ruleset|DROP\s+DATABASE|TRUNCATE\s+TABLE)'; then
    hook_ask "A broad cleanup of services or data. This needs approval for this exact operation."
fi

# Pushing where we have no business pushing. The category is the target repository's,
# not the session's: a push runs where its command runs. This used to classify the
# session directory alone, and the one push it then blocked in earnest was one the owner
# had asked for — `cd <work clone> && git push` from a session sitting in a local
# repository. So the scan is walked in segment order: `cd` moves the effective
# directory, and every push is judged in the directory it actually executes in, with
# `git -C <path>` resolved against that. Category still comes from the session cache
# when the directory is inside the cached root, and is computed without the network
# otherwise; that logic lives in repo_context, not here.

# push_step_dir <base> <token> — the directory the token lands in, or nothing when it
# cannot be known statically: a variable, a substitution, a quote the masking pass ate
# and the readback could not pin down. An empty base means "already unknown", which
# only an absolute token can repair.
push_step_dir() {
    local base="$1" tok="$2"
    case "$tok" in
        '')          printf '%s' "$HOME" ;;
        -)           : ;;
        *'$'*|*'`'*|QUOTED) : ;;
        '~')         printf '%s' "$HOME" ;;
        '~/'*)       printf '%s/%s' "$HOME" "${tok#\~/}" ;;
        '~'*)        : ;;
        /*)          printf '%s' "$tok" ;;
        *)           [ -n "$base" ] && printf '%s/%s' "$base" "$tok" ;;
    esac
}

# push_unquote_one <word-before-the-quote> — the quoted argument read back out of the
# command as written, like the rm target above. Only when the whole command has exactly
# one quoted argument in that position: two cannot be told apart by position here, so
# the directory stays unknown and the push becomes a question rather than a guess.
push_unquote_one() {
    local hits
    hits="$(printf '%s' "$CMD" | grep -oE "$1[[:space:]]+(\"[^\"]*\"|'[^']*')" |
        sed -E "s/^$1[[:space:]]+[\"']//; s/[\"']\$//")"
    [ "$(printf '%s\n' "$hits" | grep -c .)" = 1 ] || return 0
    printf '%s' "$hits"
}

CWD="$(hook_cwd)"

if printf '%s' "$SCAN" | grep -qE 'git\s[^;&|]*push'; then
    # A push segment is git (or sudo git) with only flags between it and `push`, so
    # that `git stash push` stays what it is. -C and -c carry an argument of their own.
    push_seg='^(sudo[[:space:]]+)?git[[:space:]]+((-C|-c)[[:space:]]+[^[:space:]]+[[:space:]]+|--?[^[:space:]]+[[:space:]]+)*push([[:space:]]|$)'
    DIR="$CWD"
    while IFS= read -r seg; do
        seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -n "$seg" ] || continue
        case "$seg" in
        cd|cd[[:space:]]*)
            arg="$(printf '%s' "${seg#cd}" | sed -E 's/^[[:space:]]+//; s/[[:space:]].*$//')"
            [ "$arg" = QUOTED ] && { arg="$(push_unquote_one cd)"; [ -n "$arg" ] || arg=QUOTED; }
            DIR="$(push_step_dir "$DIR" "$arg")"
            continue ;;
        esac
        printf '%s' "$seg" | grep -qE "$push_seg" || continue
        target="$DIR"
        copt="$(printf '%s' "$seg" | grep -oE '(^|[[:space:]])-C[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $2}')"
        if [ -n "$copt" ]; then
            [ "$copt" = QUOTED ] && { copt="$(push_unquote_one '[-]C')"; [ -n "$copt" ] || copt=QUOTED; }
            target="$(push_step_dir "$target" "$copt")"
        fi
        if [ -z "$target" ]; then
            hook_ask "A git push whose repository cannot be determined from the command (a variable or substitution in cd or -C). Confirm this exact push, or rewrite it with a literal path."
        fi
        repo_context "$target" "$(hook_session_id)"
        if ! policy_allow push "${REPO_CATEGORY:-foreign-no-rules}" "${RULES_MINE:-na}"; then
            hook_deny "Blocked: push in $target, a repository classified as ${REPO_CATEGORY:-foreign-no-rules} ($(policy_summary "${REPO_CATEGORY:-unknown}" "${RULES_MINE:-na}"))."
        fi
    # Process substitution, not a heredoc: an unquoted heredoc expands backticks, and
    # this one would carry them straight out of the command under judgement.
    done < <(printf '%s\n' "$SCAN" | tr ';&|' '\n')
fi

hook_allow
