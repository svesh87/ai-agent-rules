#!/usr/bin/env bash
# Put this clone in charge: the rules file, the skills, and the hooks, for both Claude
# Code and Codex. Needs no root. Safe to run again.
#
# Everything this script writes lives in the home directory, which is why it is a
# script the operator runs rather than something an agent does. It backs up whatever
# it replaces and merges into existing configuration rather than overwriting it: there
# may already be hooks on this machine that have nothing to do with this repository.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
canon="$repo/AGENTS.md"
stamp="$(date +%Y-%m-%d_%H-%M-%S)"
backup="$repo/tmp/replaced-$stamp"

[ -f "$canon" ] || { echo "no AGENTS.md beside this script: $canon" >&2; exit 1; }

claude_home="$HOME/.claude"
codex_home="${CODEX_HOME:-$HOME/.codex}"
profile_dir="${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules"

keep() {
    local target=$1
    mkdir -p "$backup"
    mv "$target" "$backup/$(printf '%s' "${target#"$HOME"/}" | tr '/' '-')"
    echo "kept $target -> $backup/"
}

# A symlink at $1 pointing to $2, idempotently.
link() {
    local target=$1 source=$2 dir
    dir="$(dirname "$target")"

    if [ ! -d "$dir" ]; then
        echo "skip $target (no $dir, tool not installed)"
        return
    fi

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
        echo "ok   $target"
        return
    fi

    [ -e "$target" ] || [ -L "$target" ] && keep "$target"

    ln -s "$source" "$target"
    echo "link $target"
}

# ---------------------------------------------------------------- gates first
# These hooks govern the tools an agent uses to fix them. A hook that denies too much
# cannot be repaired by the session it is breaking, so nothing gets registered until
# the selftest passes.
if [ -x "$repo/hooks/selftest.sh" ]; then
    echo "== hook selftest"
    if ! "$repo/hooks/selftest.sh" >/dev/null 2>&1; then
        echo "hook selftest FAILED, nothing was installed. Run $repo/hooks/selftest.sh to see why." >&2
        exit 1
    fi
    echo "ok   hooks behave as expected"
fi

# ---------------------------------------------------------------- rules file
echo
echo "== rules"
link "$claude_home/CLAUDE.md" "$canon"
link "$codex_home/AGENTS.md" "$canon"

# ---------------------------------------------------------------- skills
# The same skill directory serves both tools: each reads only its own path, and both
# follow a symlink.
#
# Two kinds are skipped. A `.repo-only` marker means the skill is about this repository
# and is already linked inside it, so it is callable straight after a clone and has no
# business appearing in every other project. A `.local` suffix means a skill that must
# not be committed, which lives next to the code it serves and is covered by the
# machine-wide ignore.
echo
echo "== skills"
if [ -d "$repo/skills" ]; then
    for tool_dir in "$claude_home" "$codex_home"; do
        [ -d "$tool_dir" ] || { echo "skip skills in $tool_dir (tool not installed)"; continue; }
        mkdir -p "$tool_dir/skills"
        for skill in "$repo"/skills/*/; do
            [ -d "$skill" ] || continue
            name="$(basename "$skill")"
            case "$name" in *.local) continue ;; esac
            if [ -f "$skill/.repo-only" ]; then
                echo "skip $name (repository-local skill)"
                continue
            fi
            link "$tool_dir/skills/$name" "${skill%/}"
        done
    done
fi

# ---------------------------------------------------------------- hooks
# Merged, never overwritten. Existing entries from other sources stay; ours are
# recognised by the path they point at, so running this again replaces only itself.
echo
echo "== hooks"
if ! command -v jq >/dev/null 2>&1; then
    echo "skip hooks (jq is not installed; hooks are registered as JSON and merged with jq)"
else
    merge_hooks() {
        local file=$1 registry=$2 wrapper=$3
        local dir; dir="$(dirname "$file")"
        [ -d "$dir" ] || { echo "skip $file (tool not installed)"; return; }

        local ours; ours="$(sed "s|__REPO__|$repo|g" "$registry")"
        local current='{}'
        if [ -f "$file" ]; then
            if ! jq empty "$file" >/dev/null 2>&1; then
                echo "skip $file (it is not valid JSON; fix it by hand and run this again)" >&2
                return
            fi
            cp "$file" "${file}.bak-$stamp"
            current="$(cat "$file")"
        fi

        # Drop any previous registration of ours, then append the current one. Entries
        # whose command does not point into this clone are left exactly as they are.
        printf '%s' "$current" | jq \
            --argjson ours "$ours" \
            --arg repo "$repo" \
            --arg wrapper "$wrapper" '
            def strip_ours:
                with_entries(
                    .value |= (map(
                        .hooks |= map(select((.command // "") | startswith($repo) | not))
                    ) | map(select((.hooks | length) > 0)))
                ) | with_entries(select((.value | length) > 0));

            def merged($existing):
                ($existing | strip_ours) as $keep
                | reduce ($ours | to_entries[]) as $e
                    ($keep; .[$e.key] = ((.[$e.key] // []) + $e.value));

            if $wrapper == "" then
                merged(.)
            else
                .[$wrapper] = merged(.[$wrapper] // {})
            end
        ' > "${file}.new"

        mv "${file}.new" "$file"
        echo "ok   $file ($(jq -r '[..|objects|select(has("command"))] | length' "$file") hook command(s) total)"
    }

    # Claude Code keeps hooks inside settings.json under a "hooks" key.
    if [ -d "$claude_home" ]; then
        [ -f "$claude_home/settings.json" ] || echo '{}' > "$claude_home/settings.json"
        merge_hooks "$claude_home/settings.json" "$repo/registry/claude-hooks.json" "hooks"
    else
        echo "skip $claude_home/settings.json (tool not installed)"
    fi

    # Codex keeps them in hooks.json under the same key. Registration goes here rather
    # than into config.toml on purpose: Codex reads both, warns when a layer uses two
    # representations, and config.toml holds credentials this script has no business
    # rewriting.
    if [ -d "$codex_home" ]; then
        [ -f "$codex_home/hooks.json" ] || echo '{}' > "$codex_home/hooks.json"
        merge_hooks "$codex_home/hooks.json" "$repo/registry/codex-hooks.json" "hooks"
    else
        echo "skip $codex_home/hooks.json (tool not installed)"
    fi
fi

# ---------------------------------------------------------------- nudge delivery
# Each agent gets its own marker. One shared marker was not enough: Claude could have the
# delivery hook while Codex did not, and the shared marker then made a Codex SessionStart
# queue a line that nobody would collect. The old marker remains for components that have
# not learned the scoped names yet.
echo
echo "== nudge delivery"
nudge_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/nudge"
nudge_command="$repo/hooks/prompt-nudge.sh"

prompt_nudge_registered() {
    local file="$1"
    jq -e --arg command "$nudge_command" '
        any(.hooks.UserPromptSubmit[]?.hooks[]?; .command == $command)
    ' "$file" >/dev/null 2>&1
}

claude_delivery=no
codex_delivery=no
prompt_nudge_registered "$claude_home/settings.json" && claude_delivery=yes
if prompt_nudge_registered "$codex_home/hooks.json"; then
    # The readiness check is a Python script, and a missing interpreter used to arrive here
    # as an empty answer, which read as "registered but not trusted". Same end state either
    # way, the marker is not written, but the diagnosis has to name the real reason: one is
    # fixed in the Codex settings and the other by installing python3.
    if ! command -v python3 >/dev/null 2>&1; then
        codex_status=no-python
    else
        codex_status="$(python3 "$repo/scripts/codex-hook-ready.py" \
            --command "$nudge_command" --cwd "$repo" 2>/dev/null || true)"
    fi
    if [ "$codex_status" = ready ]; then
        codex_delivery=yes
    elif [ "$codex_status" = no-python ]; then
        echo "--   Codex UserPromptSubmit is registered, but its trust cannot be checked"
        echo "     scripts/codex-hook-ready.py needs python3, which is not on PATH"
        echo "     install python3 and run install.sh again"
    else
        echo "--   Codex UserPromptSubmit is registered but not trusted"
        echo "     open the Codex hook settings, trust it, then run install.sh again"
        echo "     in VS Code use Codex Settings; where available, /hooks opens them"
    fi
fi

if [ "$claude_delivery" = yes ] || [ "$codex_delivery" = yes ]; then
    mkdir -p "$nudge_dir"
fi

for agent in claude codex; do
    marker="$nudge_dir/.delivery-$agent-enabled"
    case "$agent" in
        claude) ready="$claude_delivery" ;;
        codex)  ready="$codex_delivery" ;;
    esac
    if [ "$ready" = yes ]; then
        printf 'Written by install.sh: hooks/prompt-nudge.sh is registered for %s.\nComponents running under this agent may queue nudges for UserPromptSubmit.\n' \
            "$agent" > "$marker"
        echo "ok   $marker"
    else
        rm -f "$marker" 2>/dev/null || true
        echo "--   $agent delivery is not ready"
    fi
done

if [ "$claude_delivery" = yes ] || [ "$codex_delivery" = yes ]; then
    printf 'Compatibility marker for components predating per-agent delivery markers.\n' \
        > "$nudge_dir/.delivery-enabled"
else
    rm -f "$nudge_dir/.delivery-enabled" 2>/dev/null || true
    echo "--   no delivery hook is registered; components will print their lines instead"
fi

# ---------------------------------------------------------------- profile
# Which hosts and accounts are the operator's own is personal, and this repository is
# public. The classifier reads it from here; without it every unknown remote counts as
# foreign, which is the strict answer and safe.
echo
echo "== repository classifier profile"
mkdir -p "$profile_dir"
if [ -f "$profile_dir/profile.json" ]; then
    echo "ok   $profile_dir/profile.json (left as it is)"
else
    cat > "$profile_dir/profile.json" <<'JSON'
{
  "_comment": "Personal, never committed. Fill in and the session banner starts naming categories correctly.",
  "mine_hosts": ["github.com"],
  "mine_owners": [],
  "work_hosts": [],
  "work_owners": [],
  "identities": []
}
JSON
    echo "new  $profile_dir/profile.json — fill in mine_owners, work_hosts, work_owners and identities"
fi

# ---------------------------------------------------------------- machine ignore
echo
echo "== machine-wide ignore"
ignore="$(git config --global --get core.excludesFile || true)"
ignore="${ignore:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}"
ignore="${ignore/#\~/$HOME}"
mkdir -p "$(dirname "$ignore")"
touch "$ignore"

# tmp/ for drafts, *.local.md for machine-only rules, *.local/ for skills that must
# not be committed in a repository whose rules cannot be pushed.
for pattern in 'tmp/' '*.local.md' '*.local/'; do
    if grep -qxF "$pattern" "$ignore"; then
        echo "ok   $pattern in $ignore"
    else
        printf '%s\n' "$pattern" >> "$ignore"
        echo "add  $pattern to $ignore"
    fi
done

echo
echo "Rules, skills and hooks are live. Restart any running agent session to pick them up."
echo "In Codex, trust the hooks once in the hook settings, otherwise they do not run."
echo "In VS Code, open Codex Settings; where available, /hooks opens the same controls."
echo "Escape hatch if a hook ever misbehaves:"
echo "  Claude Code: claude --settings '{\"disableAllHooks\":true}'"
echo "  Codex:       untrust them in the hook settings (/hooks where available),"
echo "               or remove the entries from $codex_home/hooks.json"
