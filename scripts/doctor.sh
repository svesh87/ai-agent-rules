#!/usr/bin/env bash
# What is installed and what is missing. Changes nothing.
#
# Half of the installation lands outside the repository: symlinks in the agents' home
# directories, hook registrations, the classifier profile, the machine-wide ignore. That
# makes it easy to install half of it and then wonder why nothing fires. This is the
# report that answers that question in one screen.
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
claude_home="$HOME/.claude"
codex_home="${CODEX_HOME:-$HOME/.codex}"
profile="${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules/profile.json"

ok()   { printf '  ok    %s\n' "$*"; }
miss() { printf '  MISS  %s\n' "$*"; }
note() { printf '  --    %s\n' "$*"; }

echo "repository: $repo"

echo
echo "environment"
for tool in jq git; do
    command -v "$tool" >/dev/null 2>&1 && ok "$tool" || miss "$tool is required"
done
command -v gh >/dev/null 2>&1 && ok "gh (public/private detection)" ||
    note "gh absent: your own repositories will all be treated as public, which is the strict side"
command -v python3 >/dev/null 2>&1 && ok "python3 (Codex hook trust check)" ||
    note "python3 absent: install.sh cannot check whether the Codex hooks are trusted, so it leaves Codex nudge delivery off"
[ -d "$claude_home" ] && ok "Claude Code at $claude_home" || note "no $claude_home, Claude Code not installed"
[ -d "$codex_home" ] && ok "Codex at $codex_home" || note "no $codex_home, Codex not installed"

echo
echo "rules"
for target in "$claude_home/CLAUDE.md" "$codex_home/AGENTS.md"; do
    [ -d "$(dirname "$target")" ] || continue
    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$repo/AGENTS.md" ]; then
        ok "$target -> AGENTS.md"
    elif [ -e "$target" ]; then
        miss "$target exists but does not point here ($(readlink -f "$target" 2>/dev/null || echo 'regular file'))"
    else
        miss "$target is not linked"
    fi
done

echo
echo "skills"
for tool_dir in "$claude_home" "$codex_home"; do
    [ -d "$tool_dir" ] || continue
    linked=0 total=0
    for skill in "$repo"/skills/*/; do
        [ -d "$skill" ] || continue
        name="$(basename "$skill")"
        case "$name" in *.local) continue ;; esac
        [ -f "$skill/.repo-only" ] && continue
        total=$((total + 1))
        [ -L "$tool_dir/skills/$name" ] && [ "$(readlink -f "$tool_dir/skills/$name")" = "${skill%/}" ] &&
            linked=$((linked + 1))
    done
    if [ "$linked" = "$total" ]; then ok "$tool_dir/skills: $linked of $total"
    else miss "$tool_dir/skills: $linked of $total linked"; fi
done

echo
echo "hooks"
if command -v jq >/dev/null 2>&1; then
    for pair in "$claude_home/settings.json" "$codex_home/hooks.json"; do
        [ -d "$(dirname "$pair")" ] || continue
        if [ ! -f "$pair" ]; then miss "$pair does not exist"; continue; fi
        mine="$(jq --arg r "$repo" '[.hooks // {} | .. | objects | select(has("command")) | select(.command | startswith($r))] | length' "$pair" 2>/dev/null || echo 0)"
        other="$(jq --arg r "$repo" '[.hooks // {} | .. | objects | select(has("command")) | select(.command | startswith($r) | not)] | length' "$pair" 2>/dev/null || echo 0)"
        if [ "$mine" -gt 0 ] 2>/dev/null; then
            ok "$pair: $mine of ours, $other from elsewhere (left alone)"
        else
            miss "$pair: none of our hooks registered"
        fi
    done
else
    miss "jq absent, cannot read hook registrations"
fi
if [ -x "$repo/hooks/selftest.sh" ]; then
    if "$repo/hooks/selftest.sh" >/dev/null 2>&1; then ok "hook selftest passes"
    else miss "hook selftest FAILS: run hooks/selftest.sh"; fi
fi

echo
echo "nudge delivery"
# The one state that breaks a mechanism silently. A component files a line for the agent it
# runs under, and a marker missing for that agent sends the line into the session banner
# instead, which is the position measured not to work. Reading the markers is all this does:
# the check behind the Codex one starts a Codex process, and a report that changes nothing
# has no business doing that. install.sh runs it and says which reason applies.
nudge_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/nudge"
for pair in "claude:$claude_home" "codex:$codex_home"; do
    agent="${pair%%:*}"; home="${pair#*:}"
    [ -d "$home" ] || continue
    if [ -f "$nudge_dir/.delivery-$agent-enabled" ]; then
        ok "$agent: nudges are delivered beside the next message"
    elif [ -f "$nudge_dir/.delivery-enabled" ]; then
        note "$agent: only the pre-per-agent marker is there; run install.sh to replace it"
    else
        miss "$agent: no delivery marker, so nudges fall back to the session banner"
    fi
done

echo
echo "repository classifier profile"
if [ ! -f "$profile" ]; then
    miss "$profile does not exist: every repository will be classified as foreign"
elif command -v jq >/dev/null 2>&1; then
    empty="$(jq -r '[to_entries[] | select(.key | startswith("_") | not) | select(.value | type == "array" and length == 0) | .key] | join(", ")' "$profile" 2>/dev/null)"
    if [ -n "$empty" ]; then
        miss "$profile is incomplete, empty: $empty"
    else
        ok "$profile filled in"
    fi
fi

echo
echo "machine-wide ignore"
ignore="$(git config --global --get core.excludesFile 2>/dev/null || true)"
ignore="${ignore:-${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore}"
ignore="${ignore/#\~/$HOME}"
if [ -f "$ignore" ]; then
    for pattern in 'tmp/' '*.local.md' '*.local/'; do
        grep -qxF "$pattern" "$ignore" && ok "$pattern" || miss "$pattern missing from $ignore"
    done
else
    miss "$ignore does not exist"
fi

echo
echo "Nothing above was changed. To install or repair: ./install.sh"
echo "To take it back off, group by group with a question before each: scripts/uninstall.sh"
