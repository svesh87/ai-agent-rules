# What is allowed where.
#
# One table, keyed by the category from lib/repo-class.sh. Nothing personal lives
# here: the table says "a foreign repository is not pushed to", never which hosts
# are foreign. That part is in the profile file outside git, which is why this file
# can sit in a public repository unchanged.
#
# Answers are deliberately conservative. An unknown category answers like the
# strictest one, so a classifier that fails quietly costs a refused push, not a
# pushed secret.

# policy_allow <what> <category> [rules_mine]
#
#   push              pushing at all (still only ever on an explicit request)
#   rules-in-git      committing a rules file to this repository
#   rules-edit        editing the rules file that is already there
#   tree-footprint    leaving our own files in the work tree (settings, skills)
#   gates             running this project's tests and linters unasked
#   personal-data     real names, logins, addresses in files
#   trim-canon        deleting rules that duplicate the operator's canon
policy_allow() {
    local what="$1" cat="$2" rules_mine="${3:-na}"

    case "$what" in
    push)
        case "$cat" in
            local) return 1 ;;                       # nowhere to push
            mine-public|mine-private|work-mine|work-no-rules|work-rules) return 0 ;;
            *) return 1 ;;                           # foreign: never
        esac ;;

    rules-in-git)
        case "$cat" in
            local|mine-public|mine-private|work-mine) return 0 ;;
            *) return 1 ;;                           # work-no-rules: local file only
        esac ;;

    rules-edit)
        case "$cat" in
            local|mine-public|mine-private|work-mine) return 0 ;;
            work-rules|foreign-rules)
                [ "$rules_mine" = "yes" ] && return 0 || return 1 ;;
            *) return 1 ;;
        esac ;;

    tree-footprint)
        case "$cat" in
            local|mine-public|mine-private|work-mine|work-no-rules|work-rules) return 0 ;;
            *) return 1 ;;                           # foreign: keep it out of their tree
        esac ;;

    gates)
        # Spelled out rather than defaulted, like every other row here. It used to list the
        # refusing categories and allow the rest, which made this the one answer that got
        # looser instead of stricter on a name the table does not know. That is reachable:
        # the category also arrives from a session cache that another version of this code
        # may have written.
        case "$cat" in
            local|mine-public|mine-private|work-mine|work-no-rules|work-rules) return 0 ;;
            *) return 1 ;;                           # foreign, none, and anything unknown
        esac ;;

    personal-data)
        case "$cat" in
            local|mine-private) return 0 ;;
            *) return 1 ;;
        esac ;;

    trim-canon)
        case "$cat" in
            local|mine-private|work-mine) return 0 ;;
            mine-public) return 1 ;;                 # other readers have no canon
            work-rules|foreign-rules|foreign-no-rules|work-no-rules|none) return 1 ;;
            *) return 1 ;;
        esac ;;

    *) return 1 ;;
    esac
}

# One line a human can read, for the session banner.
policy_summary() {
    local cat="$1" rules_mine="${2:-na}"
    case "$cat" in
    none)             printf 'not a git work tree' ;;
    local)            printf 'local repository, nothing is pushed anywhere' ;;
    mine-public)      printf 'my public repository: no personal data, no host names, no local paths' ;;
    mine-private)     printf 'my private repository' ;;
    work-mine)        printf 'work repository in my namespace' ;;
    work-no-rules)    printf 'work repository without rules: keep rules in AGENTS.local.md, do not commit them' ;;
    work-rules)
        if [ "$rules_mine" = "yes" ]; then
            printf 'work repository, the rules in it are mine'
        else
            printf "work repository with someone else's rules: do not overwrite them"
        fi ;;
    foreign-no-rules) printf 'foreign repository: no push, no files left in the tree' ;;
    foreign-rules)    printf "foreign repository with its own rules: they win inside it, no push, no edits to them" ;;
    *)                printf 'unknown category, treating as foreign' ;;
    esac
}
