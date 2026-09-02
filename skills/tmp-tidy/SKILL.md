---
name: tmp-tidy
description: Tidy tmp/ on request: sort the root into the three genres, park what predates the layout, and show what the archive is holding. Triggers: "убери в tmp", "прибери tmp", "разбери tmp", a repository whose tmp/ has files loose in its root, "что там в архиве".
---

# Tidying `tmp/`

Invoked by hand, by the owner, when they want it. There is no trigger and no reminder,
and that is the deliberate shape of it: a rule that fires on an ambient condition
nobody announces does not fire at all, while a skill the owner calls cannot quietly
stop working.

The cost is that tidying happens when the owner remembers. That is accepted.

## What it does

**Sorts the root.** `tmp/` holds `work/`, `ideas/`, `archive/`, `old/` and `TODO.md`.
Anything else loose in the root is moved to `tmp/old/` as it stands, keeping its name.
This is mechanical: no judgement, no renaming, no reading.

**Never converts.** An old `FIX_PLAN_*.md`, a `CONTEXT_*.md`, a probe script is not
turned into a task folder. Those files have no spec, and reconstructing one means
inventing it — a dead document dressed as a current one is worse than a heap that
honestly looks like a heap. They stay in `old/` and are read where they lie.

**Reports the archive.** `tmp/archive/<YYYY-MM>/` and `tmp/old/` listed by age, with
sizes, so the owner can see what is being kept. Built binaries, dumps and screenshots
are named separately: those are what actually take the space.

**Proposes deletions and deletes nothing.** The list goes to the owner. Removal is
their call, one approval for one operation, and it is not this skill's to make.

**Lists what is live, on the spot and into the chat.** The tasks with the title of each
spec, the open ideas, the tray counts. Computed when asked and never written to a file:
a stored index would repeat what the layout already says and go stale between runs.
`ls tmp/work tmp/ideas` plus the first heading of each `spec.md` and `idea` file is the
whole of it.

## What it must not do

- Not touch `tmp/work/` and `tmp/ideas/`: those are already in the layout, and a task
  in progress is not clutter.
- Not delete anything, including in the system `/tmp`, where what is not ours stays.
- Not move another model's audit anywhere. It is evidence.
- Not report a file as dead because its name is unfamiliar. An unrecognised file goes
  to `old/` and is listed; that is the whole verdict.

## In a repository whose `tmp/` belongs to the project

Some projects use `tmp/` for their own build output. Then nothing is moved: say what is
there, ask where agent drafts should live, and do the rest under that answer.

## Order of work

1. Say what is loose in the root, before moving it.
2. Move it to `old/`.
3. List `old/` and `archive/` by age, with the heavy artefacts named.
4. Propose what could go, and stop there.
5. List what is live: tasks with their titles, open ideas, tray counts.
