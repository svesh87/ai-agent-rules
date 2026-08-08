*English · [Русский](README.ru.md)*

# ai-agent-rules

One person's standing rules for AI coding agents, in one file, shared by every tool
and every repository on the machine.

The rules are the kind of thing you otherwise repeat in chat every day and copy
between projects until the copies disagree: commit only when asked, nothing leaves
the working tree without approval, questions belong in the planning stage, a rule
file is not a work log. [`AGENTS.md`](AGENTS.md) is the whole of it.

## How it works

Claude Code reads `~/.claude/CLAUDE.md` and Codex reads `~/.codex/AGENTS.md`. Both
are symlinks into a clone of this repository, so there is one file to edit and both
tools see the same rules. An edit applies the moment it is saved and reaches history
through a commit and a push.

Two markers say how firm a rule is. **[hard]** cannot be overridden by a
repository. **[default]** yields to a project's own `AGENTS.md` without argument,
which is what makes the file usable in repositories that already have rules of
their own.

`AGENTS.md` is canonical and `AGENTS.ru.md` is the Russian copy. `CLAUDE.md` is a
symlink to `AGENTS.md`, which is the convention the rules themselves prescribe.

## Install

```bash
git clone git@github.com:svesh87/ai-agent-rules.git
cd ai-agent-rules
./install.sh
```

The script symlinks `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` to `AGENTS.md`
in the clone, and adds `tmp/` and `*.local.md` to the machine-wide git ignore. It
touches nothing else, needs no root, backs up whatever it is about to replace, and
is safe to run again.

Prefer to wire it up by hand:

```bash
ln -sfn "$PWD/AGENTS.md" ~/.claude/CLAUDE.md
ln -sfn "$PWD/AGENTS.md" ~/.codex/AGENTS.md
printf 'tmp/\n*.local.md\n' >> ~/.config/git/ignore
```

Where the clone lives is up to you; the symlinks carry the path, so moving it later
means running `install.sh` again.

## Updating

```bash
git pull
```

Nothing else. The symlinks point into the working tree, so a pull is the update.

Changing a rule is an edit, a commit and a push, in that order, and the edit is in
force from the moment the file is saved. The rules ask for one more step before
that: check a new point against the whole file rather than against its neighbours,
because the contradictions worth catching are the ones between distant sections.

## Making it yours

Fork it and start with the parts that are plainly one person's:

- the chat language, in the first line of **Language and tone**;
- the `pohuy` skill and the licence to swear in chat;
- the hardware key, which shapes the whole of **Git**: signing needs a physical
  touch, which is why a commit is never offered unprompted and never retried more
  than once;
- the specific tool names under **Nothing leaves on its own**, which are the MCP
  servers this machine happens to have.

The rest is not personal so much as opinionated, and it is worth reading before
deleting. The rules about `tmp/`, about audits from different models, and about
duplication between this file and a project's own exist because each of them was
paid for once already.

## Licence

MIT, see [`LICENSE`](LICENSE).
