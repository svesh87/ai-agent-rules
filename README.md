*English · [Русский](README.ru.md)*

# ai-agent-rules

One person's standing rules for AI coding agents, shared by every tool and every
repository on the machine. Not only as text: the rules that can be enforced are
enforced by hooks, and the ones that only matter at a particular moment arrive as
skills.

The rules are the kind of thing you otherwise repeat in chat every day and copy
between projects until the copies disagree: commit only when asked, nothing leaves
the working tree without approval, questions belong in the planning stage, a rule
file is not a work log.

**Worth knowing before you install it.** This reaches into both agents' own configuration:
hook registrations are merged into `~/.claude/settings.json` and `~/.codex/hooks.json`,
symlinks appear in both of their trees, and three lines go into the machine-wide git ignore.
Whatever is replaced is backed up first, only entries pointing into this clone are ever
touched, and `scripts/uninstall.sh` takes it back off group by group. Still, none of those
files are a documented interface: their shape changes between versions of the tools, so
after either one updates itself, run `scripts/doctor.sh` and read it before assuming the
hooks still fire.

## What is in here

| | |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | the rules, one line each. Canonical; `AGENTS.ru.md` is the Russian copy |
| [`docs/RATIONALE.md`](docs/RATIONALE.md) | why each rule exists. No agent reads this; it is for the person deciding |
| [`docs/mechanisms.md`](docs/mechanisms.md) | what each mechanism actually does, measured, including six places where the names lie |
| `hooks/` | nine hooks: seven enforce or remind on an observable trigger, two carry the states a skill needs to hear about |
| `skills/` | seven skills installed globally — plan, handover, context-snapshot, audit, translate, rules-edit, new-repo — plus `rules-install`, which stays here |
| `registry/` | hook registration for each tool, merged into place by `install.sh` |
| `scripts/doctor.sh` | what is installed and what is missing. Changes nothing |
| `scripts/uninstall.sh` | takes it back off, one group at a time, asking before each |
| `templates/` | the shape a work plan takes |

## How it works

Claude Code reads `~/.claude/CLAUDE.md` and Codex reads `~/.codex/AGENTS.md`. Both
are symlinks into a clone of this repository, so there is one file to edit and both
tools see the same rules. An edit applies the moment it is saved.

Two markers say how firm a rule is. **[hard]** cannot be overridden by a repository.
**[default]** yields to a project's own `AGENTS.md` without argument, which is what
makes the file usable in repositories that already have rules of their own.

Three levels of reliability, and the file says which is which. A hook is executed by
the harness, so it holds regardless of how long the session has run. A skill arrives
at the moment of work. Always-loaded text is the weakest of the three, and it gets
weaker as a session grows: the measurement behind that claim, and behind this whole
arrangement, is in [`docs/mechanisms.md`](docs/mechanisms.md).

One hook is worth naming here. `session-start.sh` works out which of eight kinds of
repository you are in — local, your own public or private, a work repository with or
without rules, someone else's with or without rules — and says what follows from it,
so that the difference between "push freely" and "never push here" is not a paragraph
somebody has to remember. Which hosts and accounts are yours is personal, so it lives
in a file outside git that `install.sh` creates.

The same hook hands Codex the contents of `AGENTS.local.md`, because Codex does not
read that file and the mechanism that looked like a substitute turns out not to be one.

## Install

```bash
git clone git@github.com:svesh87/ai-agent-rules.git
cd ai-agent-rules
./install.sh
```

Or, with an agent open in the clone, ask it to install the rules. The `rules-install`
skill is linked inside this repository already, so it is callable straight after a clone
with nothing installed yet. It reads `scripts/doctor.sh`, asks for the few things a script
must not guess — which forge accounts and git identities are yours, which host is work —
and then runs the installer. Those answers go into a file outside git, because the
classifier needs them and this repository is public.

`scripts/doctor.sh` on its own says what is in place and what is missing, and changes
nothing.

The script runs the hook selftest first and installs nothing if it fails. Then it
symlinks the rules file and every skill into both tools, merges the hook registration
into `~/.claude/settings.json` and `~/.codex/hooks.json` without disturbing hooks that
are already there, creates the classifier profile, and adds `tmp/`, `*.local.md` and
`*.local/` to the machine-wide git ignore. It needs no root, backs up whatever it is
about to replace, and is safe to run again.

In Codex, trust the hooks once in the hook settings, otherwise they do not run. In VS
Code, open Codex Settings; in interfaces that expose `/hooks`, the command opens the
same controls.

Rules only, without hooks or skills:

```bash
ln -sfn "$PWD/AGENTS.md" ~/.claude/CLAUDE.md
ln -sfn "$PWD/AGENTS.md" ~/.codex/AGENTS.md
printf 'tmp/\n*.local.md\n*.local/\n' >> ~/.config/git/ignore
```

Where the clone lives is up to you; the symlinks and the registered hook commands
carry the path, so moving it later means running `install.sh` again.

## If a hook gets in the way

It is a guard, not a verdict, and it can be wrong. Two properties are asserted by
`hooks/selftest.sh` before anything is installed: an editing tool inside the work tree
is never blocked, and a payload the hook cannot parse is allowed rather than denied.
So the way to fix a hook stays open.

To switch them all off:

```bash
claude --settings '{"disableAllHooks":true}'      # Claude Code
# Codex: untrust them in hook settings (/hooks where available), or remove the entries
# from ~/.codex/hooks.json
```

`hooks/selftest.sh` on its own says whether they behave as intended. The log is in
`~/.cache/agent-rules/hooks.log`; nothing is ever written into a repository.

## Updating

```bash
git pull
./install.sh
```

A pull is enough for the rules and the skills, since the symlinks point into the
working tree. Run the installer again when hooks were added or renamed.

Changing a rule is an edit, a commit and a push, in that order, and the edit is in
force from the moment the file is saved. The rules ask for one more step before that:
check a new point against the whole file rather than against its neighbours, because
the contradictions worth catching are the ones between distant sections.

## Taking it back off

```bash
scripts/uninstall.sh              # asks before each group
scripts/uninstall.sh --dry-run    # lists what would go, touches nothing
```

Four groups, and each is a separate question with what it costs stated before it: the
links and hook registrations, the cache with the hook log in it, the three lines in the
machine-wide git ignore, and the classifier profile. The last two are worth reading
before answering. Those ignore lines may not have been put there by this installer, and
the profile is personal and hand-written, so a reinstall brings back an empty template
rather than your answers.

Only what this clone installed is removed, recognised by where a link or a hook command
points, so hooks and skills from anywhere else survive. Backups made by the installer are
never touched: they are the way back to a configuration that came from somewhere else.

## Making it yours

Fork it and start with the parts that are plainly one person's:

- the chat language, in the first line of **Before doing anything**;
- the hardware key, which shapes the rules about commits: signing needs a physical
  touch, which is why a commit is never offered unprompted and never retried more than
  once;
- the profile the repository classifier reads, which is yours to fill in and never
  belongs in git.

The rest is not personal so much as opinionated, and it is worth reading before
deleting. The rules about `tmp/`, about audits from different models, and about
duplication between this file and a project's own exist because each of them was paid
for once already.

## Licence

MIT, see [`LICENSE`](LICENSE).
