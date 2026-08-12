# Which kind of repository is this, and are the rules in it mine?
#
# Eight kinds, the ones an operator actually distinguishes:
#
#   local              no remote, nothing is ever pushed
#   mine-public        my forge account, public
#   mine-private       my forge account, private
#   work-mine          work forge, my own namespace
#   work-no-rules      work forge, someone else's namespace, no rules file
#   work-rules         work forge, someone else's namespace, rules file present
#   foreign-no-rules   any other host, no rules file
#   foreign-rules      any other host, rules file present
#
# Plus one flag, because it cuts across the last four: RULES_MINE says whether the
# rules file in this repository was authored by the operator. A rules file I wrote
# in a work repository is mine to edit; a colleague's is not, whatever the category.
#
# What counts as "my forge" and "the work forge" is not in this repository. It is
# personal, and this repository is public. The classifier reads it from
# $XDG_CONFIG_HOME/agent-rules/profile.json, which install.sh creates from a
# template and git never sees. Without that file every unknown remote classifies as
# foreign, which is the strictest answer and therefore the safe default.

REPO_PROFILE="${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules/profile.json"
REPO_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules"

# The repository root, or empty when we are not inside a work tree.
repo_root() {
    git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf ''
}

repo_remote() {
    git -C "${1:-$PWD}" remote get-url origin 2>/dev/null || printf ''
}

# Host out of scp-style (git@host:owner/name) and URL-style remotes alike.
repo_remote_host() {
    printf '%s' "$1" | sed -E 's|^[a-z+]+://||; s|^[^@]*@||; s|[:/].*$||'
}

# First path segment after the host: the owner or top-level group.
#
# The port is dropped on the way. A forge on a non-standard SSH port gives remotes like
# ssh://git@host:2222/group/name.git, and reading the first segment blindly made the
# owner come out as the port number, so a namespace listed in the profile as the
# operator's own never matched and work-mine was unreachable. Only a numeric segment
# followed by a slash counts as a port: git@host:owner/name has no port in it.
repo_remote_owner() {
    printf '%s' "$1" | sed -E 's|^[a-z+]+://||; s|^[^@]*@||; s|^[^:/]*||; s|^:[0-9]+/|/|; s|^[:/]||; s|/.*$||'
}

_repo_profile_list() {
    # _repo_profile_list <jq-path> -> newline separated, empty when no profile
    [ -f "$REPO_PROFILE" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r "$1 // [] | .[]" "$REPO_PROFILE" 2>/dev/null || true
}

_repo_in_list() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [ "$needle" = "$item" ] && return 0
    done
    return 1
}

# The rules file this repository carries, tracked by git. An untracked AGENTS.md is
# deliberately not a rules file for classification: it exists only on this machine
# and disappears on clone, which is a state worth reporting, not relying on.
repo_rules_file() {
    local root="$1" f
    for f in AGENTS.md CLAUDE.md; do
        if [ -e "$root/$f" ] && git -C "$root" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
            printf '%s' "$f"
            return 0
        fi
    done
    printf ''
}

repo_rules_untracked() {
    local root="$1" f
    for f in AGENTS.md CLAUDE.md AGENTS.local.md CLAUDE.local.md; do
        if [ -e "$root/$f" ] && ! git -C "$root" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
            printf '%s' "$f"
            return 0
        fi
    done
    printf ''
}

# Who created the rules file. The first author is the signal, not the last: I may
# have edited a colleague's file, which does not make it mine.
repo_rules_mine() {
    local root="$1" file="$2" author
    [ -n "$file" ] || { printf 'na'; return 0; }
    author="$(git -C "$root" log --reverse --format='%ae' -- "$file" 2>/dev/null | head -1)"
    [ -n "$author" ] || { printf 'unknown'; return 0; }
    local ids; ids="$(_repo_profile_list '.identities')"
    if [ -z "$ids" ]; then printf 'unknown'; return 0; fi
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        [ "$author" = "$id" ] && { printf 'yes'; return 0; }
    done <<EOF
$ids
EOF
    printf 'no'
}

# Public or private, for my own forge only. One network call, cached forever: a
# repository does not change visibility often, and a stale answer is corrected by
# removing the cache file. When the answer cannot be had, we say public, because
# the rule that depends on it (no personal data) must not be relaxed by a timeout.
repo_visibility() {
    local host="$1" owner="$2" name="$3"
    local key="$REPO_CACHE_DIR/visibility/${host}_${owner}_${name}"
    if [ -f "$key" ]; then cat "$key"; return 0; fi
    command -v gh >/dev/null 2>&1 || { printf 'public'; return 0; }
    local out
    out="$(gh repo view "$owner/$name" --json visibility --jq '.visibility' 2>/dev/null || true)"
    case "$out" in
        PUBLIC) out=public ;;
        PRIVATE|INTERNAL) out=private ;;
        *) printf 'public'; return 0 ;;
    esac
    mkdir -p "$(dirname "$key")" 2>/dev/null && printf '%s' "$out" > "$key" 2>/dev/null
    printf '%s' "$out"
}

# repo_classify [dir] — sets REPO_ROOT, REPO_CATEGORY, REPO_RULES, RULES_MINE,
# REPO_RULES_UNTRACKED. Never fails: worst case the category is `foreign-no-rules`.
repo_classify() {
    local dir="${1:-$PWD}"
    REPO_ROOT="$(repo_root "$dir")"
    REPO_CATEGORY="none"
    REPO_RULES=""
    RULES_MINE="na"
    REPO_RULES_UNTRACKED=""

    [ -n "$REPO_ROOT" ] || return 0

    REPO_RULES="$(repo_rules_file "$REPO_ROOT")"
    REPO_RULES_UNTRACKED="$(repo_rules_untracked "$REPO_ROOT")"
    RULES_MINE="$(repo_rules_mine "$REPO_ROOT" "$REPO_RULES")"

    local remote; remote="$(repo_remote "$REPO_ROOT")"
    if [ -z "$remote" ]; then
        REPO_CATEGORY="local"
        return 0
    fi

    local host owner name
    host="$(repo_remote_host "$remote")"
    owner="$(repo_remote_owner "$remote")"
    name="$(basename "${remote%.git}")"

    local mine_hosts work_hosts mine_owners work_owners
    mine_hosts="$(_repo_profile_list '.mine_hosts')"
    work_hosts="$(_repo_profile_list '.work_hosts')"
    mine_owners="$(_repo_profile_list '.mine_owners')"
    work_owners="$(_repo_profile_list '.work_owners')"

    if printf '%s\n' "$mine_hosts" | grep -qxF "$host" 2>/dev/null &&
       printf '%s\n' "$mine_owners" | grep -qxF "$owner" 2>/dev/null; then
        case "$(repo_visibility "$host" "$owner" "$name")" in
            private) REPO_CATEGORY="mine-private" ;;
            *)       REPO_CATEGORY="mine-public" ;;
        esac
        return 0
    fi

    if printf '%s\n' "$work_hosts" | grep -qxF "$host" 2>/dev/null; then
        if printf '%s\n' "$work_owners" | grep -qxF "$owner" 2>/dev/null; then
            REPO_CATEGORY="work-mine"
        elif [ -n "$REPO_RULES" ]; then
            REPO_CATEGORY="work-rules"
        else
            REPO_CATEGORY="work-no-rules"
        fi
        return 0
    fi

    if [ -n "$REPO_RULES" ]; then
        REPO_CATEGORY="foreign-rules"
    else
        REPO_CATEGORY="foreign-no-rules"
    fi
}

# repo_context <dir> <session-id> — the same variables, from the session cache when
# it applies, computed when it does not.
#
# The cache exists so a PreToolUse hook does not classify (and possibly hit the
# network) on every tool call. It is only trusted when the directory in hand is
# actually inside the cached root: a session can move to another work tree with an
# added directory root or a plain cd, and a cache pointing at the previous one would
# make the hook judge the wrong repository. That is not hypothetical, it is what the
# selftest caught.
repo_context() {
    local dir="${1:-$PWD}" sid="${2:-}"
    local cache="$REPO_CACHE_DIR/session/$sid.env"
    if [ -n "$sid" ] && [ -f "$cache" ]; then
        # shellcheck disable=SC1090
        . "$cache" 2>/dev/null || true
        case "$dir" in
            "${REPO_ROOT:-/nonexistent}"|"${REPO_ROOT:-/nonexistent}"/*)
                [ -n "${REPO_CATEGORY:-}" ] && return 0 ;;
        esac
        REPO_ROOT=""; REPO_CATEGORY=""; REPO_RULES=""; RULES_MINE=""
    fi
    repo_classify "$dir"
}
