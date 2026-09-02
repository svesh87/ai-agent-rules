---
name: new-repo
description: Set up a repository from scratch, or bring one into line. Triggers: a new project, "создай репозиторий", "заведи репу", a repository with no rules file, no tmp/ and no gates.
---

# A repository from scratch

## Ask these first

Four answers change what gets created, and none of them can be guessed:

1. **Language of the repository's files.** English canonical with translated copies, or
   one language only.
2. **Public, private, or local without a remote.** This decides whether personal data
   may appear at all and whether a remote is created now.
3. **Tests and linters:** which, or none. Never introduce a test framework on your own
   initiative; ask, and if the answer is none, say what will be checked instead.
4. **Remote now or later.** Creating one is an outward-facing act and needs an explicit
   go-ahead.

## The layout

```
AGENTS.md            canonical rules, goes to git
AGENTS.ru.md         translated copy, if the repository keeps one
CLAUDE.md            symlink to AGENTS.md, never a regular file
AGENTS.local.md      this machine's rules, never committed
CLAUDE.local.md      symlink to AGENTS.local.md
README.md            what this is, for a human
tmp/                 tasks, ideas, drafts, artefacts. Never committed
tmp/TODO.md          the intake tray: one line and a date, nothing else touched
tmp/work/            one folder per task, <YYYY-MM-DD>-<slug>
tmp/ideas/           proposals for review, one file each, with a status
tmp/archive/         closed work, by month, whole folders
tmp/old/             whatever predates this layout. Not a source of requirements
skills/<name>/       skills specific to this repository, if any
.claude/skills/<name> -> ../../skills/<name>
.codex/skills/<name>  -> ../../skills/<name>
```

Skills that must not reach git live in `skills/<name>.local/`, which the machine-wide
ignore covers. Use that in a work repository where rules and tooling of ours are not
allowed to be committed.

## The ignore situation

Check before writing anything: `git config --global --get core.excludesFile`, then look
for `tmp/`, `*.local.md` and `*.local/` in it. When the machine-wide ignore already
covers them, the repository's own `.gitignore` needs no entry. When it does not, write
those patterns into the repository's `.gitignore`.

A directory that is not under git has nothing to ignore. Create `tmp/` and work; propose
initialising a repository where that makes sense and leave the decision to the owner.

## The rules file

Start from the operator's canon rather than from a blank page, and keep only what this
repository actually needs beyond it. What belongs in a repository's own rules file:

- what the project is, in a paragraph;
- decisions that are frozen, and why;
- safety constraints specific to this project;
- its gates, by name and command;
- test design specific to its subject;
- anything a newcomer would otherwise get wrong.

What does not belong: a restatement of process rules that live in the canon and in
skills, a directory tour that `ls` already gives, a dependency list the manifest already
gives, and generic advice about writing clean code.

The first line of `AGENTS.md` says which file is canonical and that `CLAUDE.md` is a
symlink to it.

## The first commit

Only when the owner asks for it. List what was created, show `git status`, and stop.
