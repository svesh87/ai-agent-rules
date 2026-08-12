---
name: rules-install
description: >-
  Install or repair this operator's agent rules on a machine — check what is missing,
  fill in the repository classifier, put the symlinks, skills and hooks in place for
  Claude Code and Codex. Triggers: "поставь правила", "установи это", a fresh clone of
  ai-agent-rules, a session opened here with the installation incomplete, hooks that do
  not fire.
---

# Installing the rules

This skill ships inside the repository and is linked into `.claude/skills/` and
`.codex/skills/`, so it is callable the moment the repository is cloned, before anything
has been installed. It is the only skill here that is not installed globally: outside
this repository it has nothing to do.

The work is done by `install.sh`. This skill looks at the current state, asks the owner
the things a script must not guess, and then calls it.

What it touches is worth saying out loud, because it is not this repository: hook
registrations inside `~/.claude/settings.json` and `~/.codex/hooks.json`, symlinks in both
agents' own trees, and three lines in the machine-wide git ignore. None of those are a
documented interface, and their shape changes between versions of the tools, so treat an
unexpected `doctor.sh` result after a tool update as the tool having moved rather than as
something to work around.

## Run outside a restricted sandbox

Run `scripts/doctor.sh`, `hooks/selftest.sh` and `install.sh` outside a filesystem
sandbox. The selftest creates temporary state under `~/.cache/agent-rules`, and the
installer writes links and configuration under the home directory; a sandbox limited to
the repository and `/tmp` makes those checks fail and cannot perform the installation.

Request execution outside the sandbox before running them. If the execution environment
cannot grant that access, stop and ask the owner to run the commands in a regular terminal;
do not treat the resulting `Read-only file system` failures as hook failures and do not
work around the sandbox.

## Find the repository through the symlink

No absolute path is written here on purpose.

```bash
RULES="$(readlink -f .claude/skills/rules-install/../.. 2>/dev/null || pwd)"
"$RULES/scripts/doctor.sh"
```

## 1. Look before installing

Always, even when the owner says just install it. `scripts/doctor.sh` changes nothing and
reports five blocks: environment, rules symlinks, skills, hooks, classifier profile, and
the machine-wide ignore. If everything is in place, say so and stop.

Report what is missing in one or two lines, not by pasting the whole output.

## 2. Fill in the classifier profile

Without it every repository is classified as foreign, and the session banner will refuse
pushes everywhere. The file lives outside git, at
`${XDG_CONFIG_HOME:-$HOME/.config}/agent-rules/profile.json`, because which accounts are
the owner's is personal and this repository is public.

Ask the owner directly, with the question tool rather than as prose, and only for what is
actually missing:

- **forge accounts of their own**: the host and the account name, for example the account
  under which they publish on a public forge. Fills `mine_hosts` and `mine_owners`.
- **the work forge**: its host, and which namespaces there are theirs rather than the
  team's. Fills `work_hosts` and `work_owners`. A namespace listed here counts as the
  owner's own repository, so err on the side of leaving it out.
- **git identities**: the e-mail addresses they commit under. This is what distinguishes
  "the rules file in this work repository is mine to edit" from "a colleague wrote it".
  Get them all: `git log --format='%ae' --all | sort | uniq -c | sort -rn | head` in a
  couple of their repositories gives the real list.

Write the answers with an editor, and never print a token, a key or anything else from
that directory.

## 3. Install

```bash
"$RULES/install.sh"
```

It runs the hook selftest first and installs nothing if it fails. Then it links the rules
file and the skills into both tools, merges the hook registration into
`~/.claude/settings.json` and `~/.codex/hooks.json` without touching hooks that came from
elsewhere, and adds `tmp/`, `*.local.md` and `*.local/` to the machine-wide ignore. It
backs up whatever it replaces and is safe to run again.

Everything it writes is in the home directory, which is why the owner is told what it did
rather than asked to trust it.

## 4. Say the three things that are easy to miss

- A running session does not pick any of this up. It applies to the next one.
- In Codex the hooks must be trusted once in the hook settings, or they never run. In
  VS Code, open Codex Settings; in interfaces that expose `/hooks`, the command opens
  the same controls.
- The escape hatch, in case a hook ever gets in the way:
  `claude --settings '{"disableAllHooks":true}'` for Claude Code, and untrusting them in
  the hook settings (`/hooks` where available) or removing the entries from
  `~/.codex/hooks.json` for Codex. The hook log is at
  `~/.cache/agent-rules/hooks.log`.

## Moving the clone

The symlinks and the registered hook commands carry the absolute path of the clone. After
moving it, run `install.sh` again; `doctor.sh` will show the stale links as missing.

## Taking it back off

`scripts/uninstall.sh` is the mirror of the installer: four groups, a question before each
with what it costs, and `--dry-run` to see the list without touching anything. It removes
only what this clone put there. Never run it unattended, and never answer its questions on
the owner's behalf: two of the four groups reach configuration this repository does not own.

## What this skill never does

It does not edit `~/.codex/config.toml`: credentials live there, and rewriting TOML for
one line is a bad trade. If something is needed there, `install.sh` and `doctor.sh` say
so and the owner writes the line.

It does not decide the profile's contents, and it does not install anything the owner did
not agree to. A repository classified wrongly is worse than one not classified at all:
the whole point of the banner is that "never push here" does not depend on anyone
remembering it.
