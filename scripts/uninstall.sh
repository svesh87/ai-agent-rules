#!/usr/bin/env bash
# Take all of it back off. Asks before each group and says what the group costs.
#
# The installer puts things in four different places and only one of them is obvious, so
# without this the way back is remembering all four. It is the mirror of install.sh and
# nothing else: it removes what this clone put there, recognised the same way the installer
# recognises its own work, by the path the link or the command points at.
#
# Interactive on purpose. There is no flag for taking everything without asking: the groups
# differ in what they cost, one of them can break configuration this repository never owned,
# and a script that removes all four in silence is a script nobody should run.
#
# What it never touches: the backups install.sh left behind. Those are the only way back to
# a configuration that came from somewhere else.
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_home="$HOME/.claude"
codex_home="${CODEX_HOME:-$HOME/.codex}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules"
profile_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules"
stamp="$(date +%Y-%m-%d_%H-%M-%S)"

DRY=no
case "${1:-}" in
    --dry-run) DRY=yes ;;
    "") : ;;
    *) echo "usage: $(basename "$0") [--dry-run]" >&2; exit 2 ;;
esac

say()  { printf '  %s\n' "$*"; }
risk() { printf '  risk: %s\n' "$*"; }

# confirm <question> — no is the default, and every non-yes answer is a no.
confirm() {
    local answer
    [ "$DRY" = yes ] && return 1
    printf '  %s [y/N] ' "$1"
    read -r answer || answer=""
    case "$answer" in y|Y|yes|Yes|да) return 0 ;; *) return 1 ;; esac
}

# Links that point into this clone, and only those. A file of the operator's own with the
# same name is not ours to remove.
ours_link() {
    [ -L "$1" ] && case "$(readlink -f "$1" 2>/dev/null)" in "$repo"/*|"$repo") return 0 ;; esac
    return 1
}

echo "uninstall for $repo"
[ "$DRY" = yes ] && echo "dry run: nothing will be removed"

# ---------------------------------------------------------------- links, hooks, markers
echo
echo "== rules links, skill links, hook registrations, delivery markers"
found=no
for target in "$claude_home/CLAUDE.md" "$codex_home/AGENTS.md"; do
    ours_link "$target" && { say "link  $target"; found=yes; }
done
for tool_dir in "$claude_home" "$codex_home"; do
    [ -d "$tool_dir/skills" ] || continue
    for link in "$tool_dir/skills"/*; do
        ours_link "$link" && { say "link  $link"; found=yes; }
    done
done
for file in "$claude_home/settings.json" "$codex_home/hooks.json"; do
    [ -f "$file" ] || continue
    command -v jq >/dev/null 2>&1 || continue
    n="$(jq --arg r "$repo" '[.hooks // {} | .. | objects | select(has("command"))
          | select(.command | startswith($r))] | length' "$file" 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] 2>/dev/null && { say "hooks $n of ours in $file"; found=yes; }
done
for marker in "$cache/nudge/.delivery-enabled" "$cache/nudge/.delivery-claude-enabled" \
              "$cache/nudge/.delivery-codex-enabled"; do
    [ -f "$marker" ] && { say "file  $marker"; found=yes; }
done
if [ "$found" = no ]; then
    say "nothing of ours is installed"
elif confirm "remove these?"; then
    for target in "$claude_home/CLAUDE.md" "$codex_home/AGENTS.md"; do
        ours_link "$target" && rm -f "$target" && echo "removed $target"
    done
    for tool_dir in "$claude_home" "$codex_home"; do
        [ -d "$tool_dir/skills" ] || continue
        for link in "$tool_dir/skills"/*; do
            ours_link "$link" && rm -f "$link" && echo "removed $link"
        done
    done
    for file in "$claude_home/settings.json" "$codex_home/hooks.json"; do
        [ -f "$file" ] || continue
        command -v jq >/dev/null 2>&1 || { echo "skip $file (needs jq)"; continue; }
        cp "$file" "$file.bak-$stamp"
        jq --arg r "$repo" '
            def strip_ours:
                with_entries(.value |= (map(.hooks |= map(select((.command // "")
                    | startswith($r) | not))) | map(select((.hooks | length) > 0))))
                | with_entries(select((.value | length) > 0));
            .hooks = ((.hooks // {}) | strip_ours)
            | if (.hooks | length) == 0 then del(.hooks) else . end
        ' "$file" > "$file.new" && mv "$file.new" "$file" &&
            echo "cleaned $file (kept $file.bak-$stamp)"
    done
    rm -f "$cache/nudge/.delivery-enabled" "$cache/nudge/.delivery-claude-enabled" \
          "$cache/nudge/.delivery-codex-enabled"
    echo "removed the delivery markers"
fi

# ---------------------------------------------------------------- the cache
echo
echo "== the cache"
if [ -d "$cache" ]; then
    say "directory $cache"
    say "session classifications, the nudge queue, and hooks.log"
    risk "the log goes with it, and it is the only record of what the hooks stopped"
    if confirm "remove the whole cache?"; then
        [ -n "$cache" ] && rm -rf "$cache" && echo "removed $cache"
    fi
else
    say "no $cache"
fi

# ---------------------------------------------------------------- machine-wide ignore
echo
echo "== the machine-wide ignore"
ignore="$(git config --global --get core.excludesFile 2>/dev/null || true)"
ignore="${ignore:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}"
ignore="${ignore/#\~/$HOME}"
if [ -f "$ignore" ]; then
    present=""
    for pattern in 'tmp/' '*.local.md' '*.local/'; do
        grep -qxF "$pattern" "$ignore" && present="${present:+$present, }$pattern"
    done
    if [ -n "$present" ]; then
        say "lines in $ignore: $present"
        risk "these three are not necessarily ours. Another tool, or you, may have put them"
        risk "there first, and removing them changes how git behaves in every repository"
        if confirm "remove those lines?"; then
            cp "$ignore" "$ignore.bak-$stamp"
            grep -vxF 'tmp/' "$ignore.bak-$stamp" | grep -vxF '*.local.md' |
                grep -vxF '*.local/' > "$ignore" &&
                echo "cleaned $ignore (kept $ignore.bak-$stamp)"
        fi
    else
        say "none of the three patterns are in $ignore"
    fi
else
    say "no $ignore"
fi

# ---------------------------------------------------------------- classifier profile
echo
echo "== the classifier profile"
if [ -f "$profile_dir/profile.json" ]; then
    say "file $profile_dir/profile.json"
    risk "personal and filled in by hand: which accounts and hosts are yours. A reinstall"
    risk "recreates an empty template, and every repository reads as foreign until you"
    risk "fill it in again"
    if confirm "remove the profile too?"; then
        rm -f "$profile_dir/profile.json" && echo "removed $profile_dir/profile.json"
    fi
else
    say "no $profile_dir/profile.json"
fi

echo
if [ "$DRY" = yes ]; then
    echo "Dry run over. Nothing was touched."
else
    echo "Done. A running session keeps whatever it loaded at start; the next one will not."
    echo "Backups made by install.sh are still where it left them, under $repo/tmp/."
fi
