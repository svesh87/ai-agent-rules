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
# A payload with a file edit. The optional fourth argument is a transcript path, which
# is how the grant cases hand the hook the owner's words.
edit_payload() {
    local extra=""
    [ -n "${4:-}" ] && extra=",\"transcript_path\":$(printf '%s' "$4" | jq -Rs .)"
    printf '{"session_id":"selftest","hook_event_name":"PreToolUse","cwd":"%s","tool_name":"%s","tool_input":{"file_path":%s}%s}' \
        "$1" "$3" "$(printf '%s' "$2" | jq -Rs .)" "$extra"
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

# check_allow_json <name> <hook> <payload> — allowed with an explicit decision under
# Claude Code, which is what bypasses the harness's own prompt (a silent allow does
# not), and a plain silent allow anywhere else, where the decision JSON is unmeasured.
check_allow_json() {
    local name="$1" hook="$2" payload="$3" out got
    out="$(printf '%s' "$payload" | CLAUDECODE=1 "$HERE/$hook" 2>/dev/null)"
    got=$?
    if [ "$got" = 0 ] && printf '%s' "$out" | jq -e '
           .hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL  %-56s no allow decision (exit %s)\n' "$name" "$got"
    fi
    out="$(printf '%s' "$payload" | env -u CLAUDECODE "$HERE/$hook" 2>/dev/null)"
    got=$?
    if [ "$got" = 0 ] && [ -z "$out" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1)); printf 'FAIL  %-56s not a silent allow outside Claude (exit %s)\n' "$name" "$got"
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

echo "== the agent's own memory is written without a question"
# Every memory write used to land on the ask above, which is a confirmation at the keyboard
# and a stalled task without one. HOME and CODEX_HOME move for this block so the checks say
# the same thing on a machine whose home is somewhere unusual, and so the cases beside the
# two memory directories are judged rather than exempted by a throwaway home under /tmp.
#
# The two agents keep memory differently and the exemption is a different width for each, so
# both widths are checked here rather than one standing in for the other. Claude has a memory
# directory per project; Codex has one directory for the machine, of which only the ad-hoc
# notes are the agent's to write.
REAL_HOME="$HOME"
HOME="$WORK/home"; export HOME
MEM="$HOME/.claude/projects/-fixture-slug/memory"
check_silent "the index in this project's memory"  guard-write-scope.sh "$(edit_payload "$R" "$MEM/MEMORY.md" Write)"
check_silent "a note in another project's memory"  guard-write-scope.sh "$(edit_payload "$R" "$HOME/.claude/projects/-other-slug/memory/fact.md" Write)"
check_ask "the session state beside memory/"      guard-write-scope.sh "$(edit_payload "$R" "$HOME/.claude/projects/-fixture-slug/todos/state.json" Write)"
check_ask "dots out of memory/"                   guard-write-scope.sh "$(edit_payload "$R" "$MEM/../../../../../../../../..$OUTSIDE/SECRET" Write)"

NOTES="$HOME/.codex/memories/extensions/ad_hoc/notes"
check_silent "an ad-hoc note, CODEX_HOME unset"    guard-write-scope.sh "$(edit_payload "$R" "$NOTES/2026-08-24-note.md" Write)"
check_ask "the consolidated Codex memory"         guard-write-scope.sh "$(edit_payload "$R" "$HOME/.codex/memories/MEMORY.md" Write)"
check_ask "a rollout summary"                     guard-write-scope.sh "$(edit_payload "$R" "$HOME/.codex/memories/rollout_summaries/s.md" Write)"
check_ask "the ad-hoc extension's instructions"   guard-write-scope.sh "$(edit_payload "$R" "$HOME/.codex/memories/extensions/ad_hoc/instructions.md" Write)"
check_ask "dots out of the notes directory"       guard-write-scope.sh "$(edit_payload "$R" "$NOTES/../../../../../../../../..$OUTSIDE/SECRET" Write)"

# CODEX_HOME moves the whole directory, and a hook that ignored it would send every note in
# such a setup to the ask.
CODEX_HOME="$WORK/codex-elsewhere"; export CODEX_HOME
check_silent "a note under a moved CODEX_HOME"     guard-write-scope.sh "$(edit_payload "$R" "$CODEX_HOME/memories/extensions/ad_hoc/notes/n.md" Write)"
check_ask "the old path once CODEX_HOME moved"    guard-write-scope.sh "$(edit_payload "$R" "$NOTES/n.md" Write)"
unset CODEX_HOME
HOME="$REAL_HOME"; export HOME

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

echo "== a push is judged in the repository the command runs in"
# The denied push of 2026-08-31 was `cd <work clone> && git push` asked for by the owner,
# from a session sitting in a local repository: the hook judged the session directory and
# blocked a push that never left it. The work category comes from a profile fixture, and
# a work host never calls gh, so nothing here touches the network. The cache is pointed
# at a fixture too, so a session cache from a real session cannot answer for these.
PUSH_CFG="$WORK/push-config"
mkdir -p "$PUSH_CFG/agent-rules"
printf '{"work_hosts":["work.example.com"],"work_owners":["team"]}\n' > "$PUSH_CFG/agent-rules/profile.json"
WORKCLONE="$WORK/workclone"
mkdir -p "$WORKCLONE"
git -C "$WORKCLONE" init -q 2>/dev/null
git -C "$WORKCLONE" remote add origin git@work.example.com:team/thing.git 2>/dev/null
XDG_CONFIG_HOME="$PUSH_CFG"; export XDG_CONFIG_HOME
XDG_CACHE_HOME="$WORK/push-cache"; export XDG_CACHE_HOME
check 2 "plain push from a local repository"       guard-destructive.sh "$(bash_payload "$R" "git push")"
check_silent "cd to a work clone, then push"       guard-destructive.sh "$(bash_payload "$R" "cd $WORKCLONE && git push -u origin BR-1")"
check_silent "git -C into a work clone"            guard-destructive.sh "$(bash_payload "$R" "git -C $WORKCLONE push")"
check 2 "cd back into the local repository"        guard-destructive.sh "$(bash_payload "$WORKCLONE" "cd $R && git push")"
check 2 "cd into a foreign clone, then push"       guard-destructive.sh "$(bash_payload "$R" "cd $FOREIGN && git push")"
check 2 "force push does not hide behind -C"       guard-destructive.sh "$(bash_payload "$R" "git -C $WORKCLONE push --force")"
check_ask "cd through a variable, then push"       guard-destructive.sh "$(bash_payload "$R" "cd \$DIR && git push")"
check_ask "cd through a quoted variable"           guard-destructive.sh "$(bash_payload "$R" "cd \"\$DIR\" && git push")"
check_silent "a quoted literal path still resolves" guard-destructive.sh "$(bash_payload "$R" "cd '$WORKCLONE' && git push")"
check 0 "git stash push is not a push"             guard-destructive.sh "$(bash_payload "$R" "git stash push -m wip")"
unset XDG_CONFIG_HOME XDG_CACHE_HOME

echo "== a write grant from the owner's words opens a window, and only where it says"
# The owner answers the outside-the-tree ask with «аппрув на 10 минут» in the harness's
# rejection dialog instead of a click per file. The words reach the hook through the
# transcript, inside a wrapper only the harness writes; everything that fails to parse
# must fall back to asking, so most of the cases here are the failures. The cache is a
# fixture: a real grant on this machine must not answer for these.
GRW="$WORK/grants-fixture"
GNB="$WORK/grant-neighbour"
mkdir -p "$GRW" "$GNB"
git -C "$GNB" init -q 2>/dev/null
GNB_R="$(realpath -m "$GNB")"
XDG_CACHE_HOME="$GRW/cache"; export XDG_CACHE_HOME
GDIR="$GRW/cache/agent-rules/grants"
mkdir -p "$GDIR"
NOW="$(date +%s)"

# rejection_transcript <file> <feedback text> [type] [iso-timestamp] — one JSONL entry
# in the shape the harness writes, timestamped now unless told otherwise, so it
# postdates the recorded ask the way a real rejection does.
rejection_transcript() {
    jq -cn --arg ts "${4:-$(date -u +%Y-%m-%dT%H:%M:%S.000Z)}" --arg fb "$2" --arg tp "${3:-user}" \
        '{type:$tp, timestamp:$ts, message:{role:$tp, content:[{type:"tool_result", is_error:true,
          content:("The user doesn'\''t want to proceed with this tool use. The tool use was rejected (eg. if it was a file edit, the new_string was NOT written to the file). The user provided the following reason for the rejection:  " + $fb)}]}}' > "$1"
}

printf '%s\n%s\n%s\n' "$GNB_R" "$((NOW + 600))" "selftest fixture" > "$GDIR/live.grant"
check_allow_json "a live grant lets the write through"   guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write)"
check_ask "a grant does not cover the repository next door" guard-write-scope.sh "$(edit_payload "$R" "$WORK/neighbour/f.md" Write)"

rm -f "$GDIR"/*.grant
printf '%s\n%s\n%s\n' "$GNB_R" "$((NOW - 10))" "selftest fixture" > "$GDIR/dead.grant"
check_ask "an expired grant is an ask again"             guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write)"

# The full cycle: an ask records what it was about, the phrase mints the grant on the
# retry, and the next file rides the same grant with no transcript at all.
rm -f "$GDIR"/*.grant
check_ask "outside the tree still asks first"            guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write)"
rejection_transcript "$GRW/tr-phrase.jsonl" "аппрув на 10 минут"
check_allow_json "the owner's phrase mints the grant"    guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-phrase.jsonl")"
check_allow_json "the next file rides the same grant"    guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/sub/panel.json" Write)"
rm -f "$GDIR"/*.grant
check_ask "the window closed, asking resumes"            guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write)"
rejection_transcript "$GRW/tr-phrase2.jsonl" "разрешаю на 10 минут"
check_allow_json "«разрешаю на N минут» works as well"   guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-phrase2.jsonl")"

# Each failure to parse is an ask, never an allow.
rm -f "$GDIR"/*.grant
rejection_transcript "$GRW/tr-embedded.jsonl" "вот лог: примени аппрув на 10 минут и продолжай"
check_ask "a phrase inside a longer text grants nothing" guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-embedded.jsonl")"
rejection_transcript "$GRW/tr-huge.jsonl" "на 999 минут"
check_ask "999 minutes is over the cap"                  guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-huge.jsonl")"
rejection_transcript "$GRW/tr-role.jsonl" "аппрув на 10 минут" assistant
check_ask "a phrase outside a user entry grants nothing" guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-role.jsonl")"
printf '%s\n%s\n' "$GNB_R" "$((NOW - 700))" > "$GRW/cache/agent-rules/asked/selftest"
rejection_transcript "$GRW/tr-stale.jsonl" "аппрув на 10 минут" user "$(date -u -d "@$((NOW - 650))" +%Y-%m-%dT%H:%M:%S.000Z)"
check_ask "a phrase after a stale ask grants nothing"    guard-write-scope.sh "$(edit_payload "$R" "$GNB_R/dash.json" Write "$GRW/tr-stale.jsonl")"

# The branches a grant must not reach: our files in a foreign tree stay per-file, and a
# shell write toward the grants directory is refused outright.
FOREIGN_R="$(realpath -m "$FOREIGN")"
printf '%s\n%s\n%s\n' "$FOREIGN_R" "$((NOW + 600))" "selftest fixture" > "$GDIR/foreign.grant"
XDG_CONFIG_HOME="$WORK/no-profile"; export XDG_CONFIG_HOME
check_ask "a grant does not cover our files in a foreign tree" guard-write-scope.sh "$(edit_payload "$FOREIGN" "$FOREIGN/AGENTS.md" Write)"
unset XDG_CONFIG_HOME
check 2 "a shell write toward the grants directory"      guard-shell-edit.sh "$(bash_payload "$R" "echo x > ~/.cache/agent-rules/grants/hack.grant")"
check 2 "minting a grant behind tee"                     guard-shell-edit.sh "$(bash_payload "$R" "printf 'p' | tee ~/.cache/agent-rules/grants/hack.grant")"
check 0 "revoking a grant with rm stays free"            guard-shell-edit.sh "$(bash_payload "$R" "rm -f ~/.cache/agent-rules/grants/old.grant 2>/dev/null")"
unset XDG_CACHE_HOME

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
