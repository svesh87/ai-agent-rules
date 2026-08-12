#!/usr/bin/env bash
# Run every hook against fixed payloads and check the answer.
#
# install.sh runs this and refuses to register anything if it fails. The reason is
# specific: these hooks govern the tools an agent uses to fix them. A hook that
# denies too much cannot be repaired by the session it is breaking, so the failure
# has to be caught before it reaches a session at all.
#
# Two properties matter more than any individual case and are asserted first:
# an editing tool inside the work tree is never blocked, and an unparseable payload
# is allowed rather than denied.
#
# Exit codes from a hook: 0 allow, 2 deny.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

# A payload with a shell command.
bash_payload() {
    printf '{"session_id":"selftest","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$1" "$(printf '%s' "$2" | jq -Rs .)"
}
# A payload with a file edit.
edit_payload() {
    printf '{"session_id":"selftest","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"file_path":%s}}' \
        "$1" "$3" "$(printf '%s' "$2" | jq -Rs .)"
}

# check <expected 0|2> <name> <hook> <payload>
check() {
    local want="$1" name="$2" hook="$3" payload="$4" got
    printf '%s' "$payload" | "$HERE/$hook" >/dev/null 2>&1
    got=$?
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-56s want %s, got %s\n' "$name" "$want" "$got"
    fi
}

# check_ask <name> <hook> <payload> — the call is stopped and the question goes to the
# owner. Both directions are asserted, and CLAUDECODE is set and unset explicitly rather
# than inherited: a Claude session exports it into the selftest, so a case that relied on
# the ambient value would pass under one agent and fail under the other.
#
# Under Claude Code: exit 0 with a decision in JSON, because a stopped call is not a
# failed hook. Anywhere else: exit 2 with the same text, since a harness that ignores the
# JSON would read exit 0 as permission to proceed.
# check_silent <name> <hook> <payload> — allowed with nothing said at all.
#
# Not the same as `check 0`, and the difference appeared the moment ask existed: an ask
# decision also exits 0, so a case written as `check 0` would go on passing if a silent
# allow turned into a question. The property that keeps a broken hook fixable is that an
# editing tool inside the work tree is never stopped, and only this form asserts it.
check_silent() {
    local name="$1" hook="$2" payload="$3" out got
    out="$(printf '%s' "$payload" | CLAUDECODE=1 "$HERE/$hook" 2>/dev/null)"
    got=$?
    if [ "$got" = 0 ] && [ -z "$out" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL  %-56s not a silent allow (exit %s, said %s)\n' \
            "$name" "$got" "${#out} chars"
    fi
}

check_ask() {
    local name="$1" hook="$2" payload="$3" out got
    out="$(printf '%s' "$payload" | CLAUDECODE=1 "$HERE/$hook" 2>/dev/null)"
    got=$?
    if [ "$got" = 0 ] &&
       printf '%s' "$out" | jq -e '
           .hookSpecificOutput.permissionDecision == "ask"
           and (.hookSpecificOutput.permissionDecisionReason | length > 0)' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL  %-56s no ask decision (exit %s)\n' "$name" "$got"
    fi
    printf '%s' "$payload" | env -u CLAUDECODE "$HERE/$hook" >/dev/null 2>&1
    got=$?
    if [ "$got" = 2 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL  %-56s did not fall back to a refusal (exit %s)\n' "$name" "$got"
    fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required to run the selftest"; exit 1; }

# The fixture repository must not live under /tmp: the write-scope hook exempts
# scratch space on purpose, and a fixture inside it would make half these checks
# pass without proving anything. Our own cache directory is the nearest place that
# belongs to this tooling rather than to the operator.
FIXTURE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules"
case "$(realpath -m "$FIXTURE_BASE" 2>/dev/null || printf '%s' "$FIXTURE_BASE")" in
    /tmp/*|/var/tmp/*)
        # The cache resolves into scratch space, which is what happens when the installer is
        # exercised with a throwaway HOME, and that is exactly how the uninstaller gets
        # tested. Leaving the fixture there would exempt five boundary cases instead of
        # checking them, so it moves beside the repository, where tmp/ is ignored by git.
        FIXTURE_BASE="$HERE/../tmp/selftest-fixtures" ;;
esac
mkdir -p "$FIXTURE_BASE" 2>/dev/null ||
    { echo "cannot create a fixture directory at $FIXTURE_BASE"; exit 1; }
WORK="$(mktemp -d "$FIXTURE_BASE/selftest.XXXXXX")"
# The base goes too when it was ours to create and nothing else is left in it.
trap 'rm -rf "$WORK"; rmdir "$FIXTURE_BASE" 2>/dev/null || true' EXIT
mkdir -p "$WORK/repo/tmp" "$WORK/repo/src"
git -C "$WORK/repo" init -q 2>/dev/null
: > "$WORK/repo/src/main.rs"
: > "$WORK/repo/README.md"
R="$WORK/repo"

# A path that stands for "outside every work tree", for the cases about the boundary. It is
# never created and never written to, only judged, so it does not have to exist.
#
# It used to be $HOME, and that was a mistake of the same family as the fixture under /tmp.
# Run the installer with a throwaway HOME under /tmp, which is exactly how one tests the
# uninstaller, and every such case silently tested the scratch exemption instead of the
# boundary, failed, and took install.sh down with it, since the installer gates on this
# selftest.
OUTSIDE="/var/lib/agent-rules-nowhere"

echo "== the two properties that keep a broken hook fixable"
check_silent "Edit inside the work tree is allowed"        guard-write-scope.sh "$(edit_payload "$R" "$R/src/main.rs" Edit)"
check_silent "Write inside the work tree is allowed"       guard-write-scope.sh "$(edit_payload "$R" "$R/README.md" Write)"
check_silent "Edit of a hook script itself is allowed"     guard-write-scope.sh "$(edit_payload "$R" "$R/hooks/guard-shell-edit.sh" Edit)"
check_silent "apply_patch inside the work tree is allowed" guard-write-scope.sh "$(edit_payload "$R" "$R/src/main.rs" apply_patch)"

echo "== an unparseable or empty payload is allowed, never denied"
for h in guard-shell-edit.sh guard-destructive.sh guard-write-scope.sh prose-check.sh note-gates.sh stop-gates.sh session-start.sh pre-compact.sh prompt-nudge.sh; do
    check 0 "empty stdin: $h"      "$h" ""
    check 0 "garbage stdin: $h"    "$h" "not json at all"
    check 0 "empty object: $h"     "$h" "{}"
done

echo "== shell edits of tracked files are blocked"
check 2 "python read/replace/write"      guard-shell-edit.sh "$(bash_payload "$R" "python3 - <<'PY'
import pathlib
p = pathlib.Path('src/main.rs'); s = p.read_text()
p.write_text(s.replace('a','b'))
PY")"
check 2 "sed -i"                         guard-shell-edit.sh "$(bash_payload "$R" "sed -i 's/a/b/' README.md")"
check 2 "perl -i"                        guard-shell-edit.sh "$(bash_payload "$R" "perl -i -pe 's/a/b/' src/main.rs")"
check 2 "redirect onto a source file"    guard-shell-edit.sh "$(bash_payload "$R" "cat > src/main.rs <<'EOF'
fn main() {}
EOF")"
check 2 "append onto a document"         guard-shell-edit.sh "$(bash_payload "$R" "echo done >> README.md")"
check 2 "tee onto a document"            guard-shell-edit.sh "$(bash_payload "$R" "echo x | tee README.md")"

echo "== legitimate shell work is not blocked"
check 0 "reading a file"                 guard-shell-edit.sh "$(bash_payload "$R" "cat README.md | head -20")"
check 0 "grep over sources"              guard-shell-edit.sh "$(bash_payload "$R" "grep -rn 'fn main' src/")"
check 0 "generating into tmp/"           guard-shell-edit.sh "$(bash_payload "$R" "python3 gen.py > tmp/report.md")"
check 0 "writing under /tmp"             guard-shell-edit.sh "$(bash_payload "$R" "sed -i 's/a/b/' /tmp/scratch.md")"
check 0 "building"                       guard-shell-edit.sh "$(bash_payload "$R" "cargo build --release 2>&1 | tail -5")"
check 0 "git status"                     guard-shell-edit.sh "$(bash_payload "$R" "git status --short")"

echo "== destructive commands"
check 2 "--no-gpg-sign"                  guard-destructive.sh "$(bash_payload "$R" "git commit --no-gpg-sign -m x")"
check 2 "push --force"                   guard-destructive.sh "$(bash_payload "$R" "git push --force origin main")"
check 2 "push -f"                        guard-destructive.sh "$(bash_payload "$R" "git push -f")"
check 2 "reset --hard"                   guard-destructive.sh "$(bash_payload "$R" "git reset --hard origin/main")"
check_ask "rm -rf outside tmp"           guard-destructive.sh "$(bash_payload "$R" "rm -rf build/")"
check_ask "docker system prune"          guard-destructive.sh "$(bash_payload "$R" "docker system prune -af")"
check 0 "rm -rf inside tmp"              guard-destructive.sh "$(bash_payload "$R" "rm -rf tmp/old")"
# Recursion is the dangerous half, and the pattern used to demand both letters. The long
# option and a sudo in front were not considered at all.
check_ask "rm -r without the f"          guard-destructive.sh "$(bash_payload "$R" "rm -r build/")"
check_ask "rm --recursive"               guard-destructive.sh "$(bash_payload "$R" "rm --recursive build/")"
check_ask "sudo rm -rf"                  guard-destructive.sh "$(bash_payload "$R" "sudo rm -rf /opt/app")"
check 0 "rm -r inside tmp"               guard-destructive.sh "$(bash_payload "$R" "rm -r tmp/old")"
check 0 "rm -f of one file"              guard-destructive.sh "$(bash_payload "$R" "rm -f build/artifact.o")"
check 0 "rm -rf under /tmp"              guard-destructive.sh "$(bash_payload "$R" "rm -rf /tmp/scratch-dir")"
check 0 "ordinary commit"                guard-destructive.sh "$(bash_payload "$R" "git commit -F tmp/commit-message.txt")"
check 0 "rm of one file"                 guard-destructive.sh "$(bash_payload "$R" "rm build/artifact.o")"

# A quoted string is data, an executor's payload is a command. Both halves were wrong at
# once: a commit message or a grep pattern that merely named an operation was denied, and a
# real recursive delete behind bash -c or ssh went through. The tmp/ exemption has to
# survive quoting, or the fix would only move the false positive.
check 0 "a message naming a force push"  guard-destructive.sh "$(bash_payload "$R" "git commit -m 'do not use git push --force here'")"
check 0 "a grep pattern naming a delete" guard-destructive.sh "$(bash_payload "$R" "grep -niE 'flock|rm -rf|nudge' hooks/selftest.sh")"
check 0 "a message naming a prune"       guard-destructive.sh "$(bash_payload "$R" "echo 'docker system prune is banned'")"
check_ask "delete behind bash -c"        guard-destructive.sh "$(bash_payload "$R" "bash -c 'rm -rf /srv/build'")"
check_ask "delete behind ssh"            guard-destructive.sh "$(bash_payload "$R" "ssh host 'rm -rf /var/lib/data'")"
check_ask "delete behind sudo sh -c"     guard-destructive.sh "$(bash_payload "$R" "sudo sh -c 'rm -rf /opt/app'")"
check 2 "force push behind ssh"          guard-destructive.sh "$(bash_payload "$R" "ssh host 'git push --force'")"
check_ask "delete through xargs"         guard-destructive.sh "$(bash_payload "$R" "find . -name '*.o' | xargs rm -rf")"
check 0 "quoted tmp/ path stays exempt"  guard-destructive.sh "$(bash_payload "$R" "rm -rf 'tmp/old'")"
check 0 "xargs delete inside tmp/"       guard-destructive.sh "$(bash_payload "$R" "find tmp -name '*.o' | xargs rm -rf tmp/build")"

echo "== writing outside the work tree"
check_ask "a path outside any repository" guard-write-scope.sh "$(edit_payload "$R" "$OUTSIDE/rc" Write)"
check_ask "another repository"           guard-write-scope.sh "$(edit_payload "$R" "$WORK/other/AGENTS.md" Write)"
check 0 "system temporary directory"     guard-write-scope.sh "$(edit_payload "$R" "/tmp/scratch.md" Write)"

echo "== the boundary is compared as paths, not as strings"
# Four of these five shapes used to pass as a silent allow. The clearest was the same file
# refused when named absolutely and allowed when named with enough dots, so leaving the tree
# never needed a symlink. The neighbour repository and the link into it are built here
# rather than in the shared fixture, because only these cases need them.
mkdir -p "$WORK/neighbour/tmp"
git -C "$WORK/neighbour" init -q 2>/dev/null
ln -sfn "$WORK/neighbour" "$R/engine"
check_ask "the repository next door, absolute"   guard-write-scope.sh "$(edit_payload "$R" "$WORK/neighbour/tmp/PROBE.md" Write)"
check_ask "out through a symlink, relative"      guard-write-scope.sh "$(edit_payload "$R" "engine/tmp/PROBE.md" Write)"
check_ask "out through a symlink, absolute"      guard-write-scope.sh "$(edit_payload "$R" "$R/engine/tmp/PROBE.md" Write)"
check_ask "dots into the repository next door"   guard-write-scope.sh "$(edit_payload "$R" "../neighbour/tmp/PROBE.md" Write)"
check_ask "dots as far as somewhere else"        guard-write-scope.sh "$(edit_payload "$R" "../../../../../../..$OUTSIDE/SECRET" Write)"
check_silent "a path inside the tree, relative"  guard-write-scope.sh "$(edit_payload "$R" "src/main.rs" Edit)"
check_silent "a path inside tmp/, relative"      guard-write-scope.sh "$(edit_payload "$R" "tmp/report.md" Write)"
rm -f "$R/engine"

echo "== a foreign checkout keeps our files out and its own code alone"
# The branch for this was below the in-tree allow and therefore dead, so the rule had never
# been enforced once. Reviving it wholesale would have been worse than dead: a question on
# every file in a foreign repository turns work on an upstream project into clicking.
# Foreign is produced by giving the fixture a remote and taking the profile away, which is
# what makes every unknown host foreign.
FOREIGN="$WORK/foreign"
mkdir -p "$FOREIGN/src" "$FOREIGN/.claude" "$FOREIGN/tmp"
git -C "$FOREIGN" init -q 2>/dev/null
git -C "$FOREIGN" remote add origin https://example.com/someone/thing.git 2>/dev/null
XDG_CONFIG_HOME="$WORK/no-profile"; export XDG_CONFIG_HOME
check_silent "their own code is edited quietly"   guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/src/main.rs" Edit)"
check_silent "a draft under their tmp/"           guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/tmp/NOTES.md" Write)"
check_ask "our rules file in their tree"          guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/AGENTS.md" Write)"
check_ask "our local rules in their tree"         guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/AGENTS.local.md" Write)"
check_ask "our agent directory in their tree"     guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/.claude/settings.json" Write)"
unset XDG_CONFIG_HOME

echo "== prose check warns and never blocks"
printf 'A line with an em dash — like this, and delve into it.\n' > "$R/bad.md"
check 0 "markers found: still allowed"   prose-check.sh "$(edit_payload "$R" "$R/bad.md" Write)"
printf 'Examples in backticks are exempt: `—`, `delve`, `not just X, but Y`.\n' > "$R/quoted.md"
check 0 "markers in backticks"           prose-check.sh "$(edit_payload "$R" "$R/quoted.md" Write)"
if printf '%s' "$(edit_payload "$R" "$R/quoted.md" Write)" | "$HERE/prose-check.sh" 2>&1 | grep -q 'em dash'; then
    FAIL=$((FAIL + 1)); echo "FAIL  backtick example still tripped the prose check"
else
    PASS=$((PASS + 1))
fi
if printf '%s' "$(edit_payload "$R" "$R/bad.md" Write)" | "$HERE/prose-check.sh" 2>&1 | grep -q 'em dash'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  a real em dash was not reported"
fi

echo "== a remote is read the same whatever shape it comes in"
# Everything the classifier decides hangs off the host and the owner it reads out of the
# remote, so a shape it misreads puts the repository in the wrong category. The port form
# is the one that was wrong: the owner came out as the port number, which meant a work
# forge namespace listed in the profile as the operator's own could never match it.
# shellcheck source=../lib/repo-class.sh
. "$HERE/../lib/repo-class.sh"
remote_case() {
    local remote="$1" want_host="$2" want_owner="$3" host owner
    host="$(repo_remote_host "$remote")"
    owner="$(repo_remote_owner "$remote")"
    if [ "$host" = "$want_host" ] && [ "$owner" = "$want_owner" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL  %-48s want %s/%s, got %s/%s\n' "$remote" "$want_host" "$want_owner" "$host" "$owner"
    fi
}
remote_case 'ssh://git@forge.example.com:2222/group/name.git' forge.example.com group
remote_case 'ssh://git@forge.example.com/group/name.git'      forge.example.com group
remote_case 'git@forge.example.com:owner/name.git'            forge.example.com owner
remote_case 'https://forge.example.com/owner/name'            forge.example.com owner
remote_case 'https://forge.example.com:8443/owner/name.git'   forge.example.com owner

echo "== a session cache from another work tree is ignored, not obeyed"
# Regression: the cache was trusted unconditionally, so a cache written while the
# session sat in another repository made the hook judge this one by the wrong root
# and deny edits inside the current tree.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/agent-rules/session"
mkdir -p "$CACHE_DIR"
printf 'REPO_ROOT=%q\nREPO_CATEGORY=%q\nREPO_RULES=%q\nRULES_MINE=%q\n' \
    "$WORK/somewhere-else" "foreign-no-rules" "" "na" > "$CACHE_DIR/selftest-stale.env"
STALE='{"session_id":"selftest-stale","hook_event_name":"PreToolUse","cwd":"'"$R"'","tool_name":"Edit","tool_input":{"file_path":"'"$R"'/src/main.rs"}}'
check 0 "stale cache does not block an in-tree edit" guard-write-scope.sh "$STALE"
rm -f "$CACHE_DIR/selftest-stale.env"

echo "== session start produces valid JSON"
# The fixture repository carries no rules file, so this banner files a nudge on its way
# out. It goes to a cache inside the fixture: with the operator's own the selftest left a
# nudge sitting in the live queue, waiting for a session that never comes.
if printf '{"session_id":"selftest","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
   XDG_CACHE_HOME="$WORK/cache-banner" "$HERE/session-start.sh" 2>/dev/null | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  session-start.sh did not produce additionalContext"
fi

echo "== states that a skill handles reach the prompt, not just the banner"
# The ambient triggers. A skill that fires on state needs the state said aloud, and said
# where it carries weight: beside the owner's message, not above it. Both halves of that
# round trip are asserted here, because either one failing silently is exactly the defect
# this mechanism exists to fix.
#
# The queue lives under XDG_CACHE_HOME, and both halves need it in a different state, so
# each gets a cache of its own inside the fixture: this one with the delivery marker in
# it, the fallback below without. An earlier version borrowed the operator's live queue
# and toggled the real marker instead, which made the fallback case depend on whether
# install.sh had ever run on the machine: it passed before installation and failed after.
NUDGE_CACHE="$WORK/cache-delivery-on"
NUDGE_DIR="$NUDGE_CACHE/agent-rules/nudge"
mkdir -p "$NUDGE_DIR"
: > "$NUDGE_DIR/.delivery-enabled"
printf '{"session_id":"selftest-nudge","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    XDG_CACHE_HOME="$NUDGE_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" >/dev/null 2>&1
for want in rules-install new-repo; do
    if grep -q "$want" "$NUDGE_DIR/selftest-nudge" 2>/dev/null; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL  session start left no nudge naming $want"
    fi
done
DELIVERED="$(printf '{"session_id":"selftest-nudge","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"привет"}' "$R" |
    XDG_CACHE_HOME="$NUDGE_CACHE" "$HERE/prompt-nudge.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if printf '%s' "$DELIVERED" | grep -q 'rules-install'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the nudge was not delivered on the next prompt"
fi
AGAIN="$(printf '{"session_id":"selftest-nudge","hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"ещё"}' "$R" |
    XDG_CACHE_HOME="$NUDGE_CACHE" "$HERE/prompt-nudge.sh" 2>/dev/null)"
if [ -z "$AGAIN" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the nudge repeated on the second prompt instead of being cleared"
fi

echo "== one agent's delivery marker does not promise delivery by the other"
# Which agent a hook belongs to is read from CLAUDECODE, which a Claude Code session
# exports into everything it runs, this selftest included. So the cases that stand in for
# a Codex hook unset it: without that they pass when Codex runs the selftest and fail when
# Claude does, and install.sh gates on the selftest, which would make a machine refuse to
# install from inside a Claude session.
SCOPED_CACHE="$WORK/cache-scoped-delivery"
SCOPED_DIR="$SCOPED_CACHE/agent-rules/nudge"
mkdir -p "$SCOPED_DIR"
: > "$SCOPED_DIR/.delivery-claude-enabled"
CODEX_FALLBACK="$(printf '{"session_id":"selftest-codex-no-delivery","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    env -u CLAUDECODE XDG_CACHE_HOME="$SCOPED_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" 2>/dev/null)"
if printf '%s' "$CODEX_FALLBACK" | jq -e '.hookSpecificOutput.additionalContext | contains("rules-install")' >/dev/null 2>&1 &&
   [ ! -f "$SCOPED_DIR/selftest-codex-no-delivery" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  a Claude marker enabled the Codex nudge queue"
fi

printf '{"session_id":"selftest-claude-delivery","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    CLAUDECODE=1 XDG_CACHE_HOME="$SCOPED_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" >/dev/null 2>&1
if grep -q 'rules-install' "$SCOPED_DIR/selftest-claude-delivery" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the Claude marker did not enable the Claude nudge queue"
fi

rm -f "$SCOPED_DIR/.delivery-claude-enabled"
: > "$SCOPED_DIR/.delivery-codex-enabled"
printf '{"session_id":"selftest-codex-delivery","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    env -u CLAUDECODE XDG_CACHE_HOME="$SCOPED_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" >/dev/null 2>&1
if grep -q 'rules-install' "$SCOPED_DIR/selftest-codex-delivery" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the Codex marker did not enable the Codex nudge queue"
fi

echo "== the gate reminder knows whether the gates ran"
# The only mechanism here whose failure is completely silent: a reminder that does not
# arrive looks exactly like a turn that did not need one. Until now both halves of it were
# covered by nothing but the parse-failure property.
#
# The cache is inside the fixture, so nothing here writes into the operator's own. The
# fixture needs no commit to look changed: its files were never committed, so
# `git status --porcelain` is not empty, and with no remote the category is `local`, which
# is a category that runs its gates.
GATES_CACHE="$WORK/cache-gates"
GATES_SESSION="$GATES_CACHE/agent-rules/session"
mkdir -p "$GATES_SESSION"

printf '%s' "$(bash_payload "$R" "pytest -q")" |
    XDG_CACHE_HOME="$GATES_CACHE" "$HERE/note-gates.sh" >/dev/null 2>&1
if [ -f "$GATES_SESSION/selftest.gates" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  a gate command left no marker for the reminder to find"
fi

rm -f "$GATES_SESSION/selftest.gates"
printf '%s' "$(bash_payload "$R" "ls -la")" |
    XDG_CACHE_HOME="$GATES_CACHE" "$HERE/note-gates.sh" >/dev/null 2>&1
if [ -f "$GATES_SESSION/selftest.gates" ]; then
    FAIL=$((FAIL + 1)); echo "FAIL  an ordinary command counted as a gate run"
else
    PASS=$((PASS + 1))
fi

# The machine-wide ignore file is kept out of it, because it carries `tmp/`: with it in
# force the fixture below looks clean to git no matter what the hook does, and the case
# meant to prove the hook's own tmp/ exemption passes for somebody else's reason. Found by
# mutating the hook and watching the case fail to notice. `GIT_CONFIG_GLOBAL` is not the
# lever here, since git reads `$XDG_CONFIG_HOME/git/ignore` by default with no
# configuration involved; pointing that variable at the fixture is.
stop_gates_says() {
    printf '{"session_id":"selftest","hook_event_name":"Stop","cwd":"%s"}' "$1" |
        XDG_CONFIG_HOME="$WORK/no-profile" XDG_CACHE_HOME="$GATES_CACHE" \
        "$HERE/stop-gates.sh" 2>&1 >/dev/null
}
if printf '%s' "$(stop_gates_says "$R")" | grep -q 'no test or lint command ran'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  a changed tree with no gate run drew no reminder"
fi

: > "$GATES_SESSION/selftest.gates"
if [ -z "$(stop_gates_says "$R")" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the reminder came anyway after the gates had run"
fi
rm -f "$GATES_SESSION/selftest.gates"

# Only tmp/ changed, which is the exemption the filter in stop-gates.sh exists for, so this
# doubles as the case for a tree that has nothing worth reminding about.
QUIET="$WORK/quiet-repo"
mkdir -p "$QUIET/tmp"
git -C "$QUIET" init -q 2>/dev/null
printf 'draft\n' > "$QUIET/tmp/notes.md"
if [ -z "$(stop_gates_says "$QUIET")" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  a change confined to tmp/ drew a reminder"
fi

echo "== a nudge nobody collected does not wait forever"
# The queue is only read on a prompt, so a session that ends before sending one leaves its
# line behind, and a resumed session brings the id back. The sweep takes the stale line and
# nothing else: not a fresh one, and not the delivery markers, which are dotfiles.
SWEEP_CACHE="$WORK/cache-sweep"
SWEEP_DIR="$SWEEP_CACHE/agent-rules/nudge"
mkdir -p "$SWEEP_DIR"
: > "$SWEEP_DIR/.delivery-claude-enabled"
printf -- '- a line from a session that never prompted\n' > "$SWEEP_DIR/dead-session"
touch -d '2 days ago' "$SWEEP_DIR/dead-session" 2>/dev/null ||
    touch -t "$(date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null || echo 202001010000)" "$SWEEP_DIR/dead-session"
printf -- '- a line filed a moment ago\n' > "$SWEEP_DIR/live-session"
printf '{"session_id":"selftest-sweep","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    CLAUDECODE=1 XDG_CACHE_HOME="$SWEEP_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" >/dev/null 2>&1
if [ ! -f "$SWEEP_DIR/dead-session" ] && [ -f "$SWEEP_DIR/live-session" ] &&
   [ -f "$SWEEP_DIR/.delivery-claude-enabled" ]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the sweep took the wrong files, or none"
fi

echo "== the chat register is switched by a nudge, not by hoping"
# The register and the language of the chat are decided before the first sentence, so the
# instruction has to arrive before it. The skill is a plugin living in the agent's own tree,
# which is why the check is against HOME rather than anything in this repository, and why a
# machine without the skill must get no line about it.
REG_CACHE="$WORK/cache-register"
REG_DIR="$REG_CACHE/agent-rules/nudge"
mkdir -p "$REG_DIR" "$WORK/home-with-skill/.claude/skills/pohuy" "$WORK/home-bare"
: > "$REG_DIR/.delivery-claude-enabled"
printf '{"session_id":"selftest-register","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    CLAUDECODE=1 HOME="$WORK/home-with-skill" XDG_CACHE_HOME="$REG_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" \
    "$HERE/session-start.sh" >/dev/null 2>&1
if grep -q 'pohuy' "$REG_DIR/selftest-register" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  the register nudge was not filed where the skill is installed"
fi
printf '{"session_id":"selftest-no-register","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    CLAUDECODE=1 HOME="$WORK/home-bare" XDG_CACHE_HOME="$REG_CACHE" XDG_CONFIG_HOME="$WORK/no-profile" \
    "$HERE/session-start.sh" >/dev/null 2>&1
if grep -q 'pohuy' "$REG_DIR/selftest-no-register" 2>/dev/null; then
    FAIL=$((FAIL + 1)); echo "FAIL  the register nudge was filed on a machine without the skill"
else
    PASS=$((PASS + 1))
fi

echo "== Codex delivery readiness includes hook trust"
if command -v python3 >/dev/null 2>&1; then
    FAKE_BIN="$WORK/fake-codex-bin"
    mkdir -p "$FAKE_BIN"
    printf '%s\n' \
        '#!/bin/sh' \
        'while IFS= read -r line; do' \
        '  case "$line" in' \
        '    *"\"id\": 0"*) printf '\''{"id":0,"result":{}}\n'\'' ;;' \
        '    *"\"method\": \"hooks/list\""*) printf '\''{"id":1,"result":{"data":[{"cwd":"/repo","hooks":[{"eventName":"userPromptSubmit","command":"/rules/hooks/prompt-nudge.sh","enabled":true,"trustStatus":"%s"}]}]}}\n'\'' "${FAKE_TRUST_STATUS:-untrusted}" ;;' \
        '  esac' \
        'done' > "$FAKE_BIN/codex"
    chmod +x "$FAKE_BIN/codex"

    if FAKE_TRUST_STATUS=trusted PATH="$FAKE_BIN:$PATH" \
       python3 "$HERE/../scripts/codex-hook-ready.py" \
           --command /rules/hooks/prompt-nudge.sh --cwd /repo >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); echo "FAIL  a trusted Codex delivery hook was not ready"
    fi
    if FAKE_TRUST_STATUS=untrusted PATH="$FAKE_BIN:$PATH" \
       python3 "$HERE/../scripts/codex-hook-ready.py" \
           --command /rules/hooks/prompt-nudge.sh --cwd /repo >/dev/null 2>&1; then
        FAIL=$((FAIL + 1)); echo "FAIL  an untrusted Codex hook was marked ready"
    else
        PASS=$((PASS + 1))
    fi
fi

# Without delivery a nudge must land in the banner rather than vanish, and the banner must
# stay valid JSON: the first version of this printed the line straight to stdout and broke
# it. A cache directory with no marker in it is what "delivery off" means here, so the
# case says the same thing on a machine where the rules are installed and one where they
# are not.
FALLBACK="$(printf '{"session_id":"selftest-fallback","hook_event_name":"SessionStart","cwd":"%s"}' "$R" |
    XDG_CACHE_HOME="$WORK/cache-delivery-off" XDG_CONFIG_HOME="$WORK/no-profile" "$HERE/session-start.sh" 2>/dev/null)"
if printf '%s' "$FALLBACK" | jq -e '.hookSpecificOutput.additionalContext | contains("rules-install")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  with delivery off, the nudge did not fall back into valid banner JSON"
fi

PRECOMPACT="$(printf '{"session_id":"selftest","hook_event_name":"PreCompact","cwd":"%s"}' "$R" |
    "$HERE/pre-compact.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
if printf '%s' "$PRECOMPACT" | grep -q 'context-snapshot'; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL  PreCompact did not name context-snapshot"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
