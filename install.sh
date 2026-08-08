#!/usr/bin/env bash
# Point Claude Code and Codex at AGENTS.md in this clone, and keep agent scratch
# files out of git machine-wide. Needs no root. Safe to run again.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
canon="$repo/AGENTS.md"
backup="$repo/tmp/replaced-$(date +%Y-%m-%d_%H-%M-%S)"

[ -f "$canon" ] || { echo "no AGENTS.md beside this script: $canon" >&2; exit 1; }

link() {
    local target=$1 dir
    dir="$(dirname "$target")"

    if [ ! -d "$dir" ]; then
        echo "skip $target (no $dir, tool not installed)"
        return
    fi

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$canon" ]; then
        echo "ok   $target"
        return
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        mkdir -p "$backup"
        mv "$target" "$backup/$(basename "$dir")-$(basename "$target")"
        echo "kept $target -> $backup/"
    fi

    ln -s "$canon" "$target"
    echo "link $target"
}

link "$HOME/.claude/CLAUDE.md"
link "$HOME/.codex/AGENTS.md"

# Machine-wide ignore. Git reads this path by default; respect an existing setting.
ignore="$(git config --global --get core.excludesFile || true)"
ignore="${ignore:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}"
ignore="${ignore/#\~/$HOME}"
mkdir -p "$(dirname "$ignore")"
touch "$ignore"

for pattern in 'tmp/' '*.local.md'; do
    if grep -qxF "$pattern" "$ignore"; then
        echo "ok   $pattern in $ignore"
    else
        printf '%s\n' "$pattern" >> "$ignore"
        echo "add  $pattern to $ignore"
    fi
done

echo
echo "Rules are live. Restart any running agent session to pick them up."
