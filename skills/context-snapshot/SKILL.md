---
name: context-snapshot
description: Save the state of the work: append to the task's journal.md along the way, rewrite context.md at handover. Triggers: "сохрани контекст", "зафиксируй состояние", a nudge about bookkeeping debt, a decision or measurement that exists only in the conversation, end of an iteration.
---

# Saving the state of the work

Two files, and the difference between them is cost.

`journal.md` in the task folder is **appended to and never rewritten**. Three lines are
a legitimate entry. It is written along the way, many times, and it is the only thing
that survives compaction, because compaction gives no turn in which to write anything.

`context.md` in the same folder is **rewritten once**, at handover or when the owner
asks. It is a snapshot for someone arriving with an empty context.

The split exists because the old arrangement was one file that had to be rewritten in
full every time. That is expensive, so it got deferred, and the deferral ran past the
edge of the context window. Cheap enough to actually do beats complete and skipped.

## The journal

Reasons, not chronology. What was decided and why, what a measurement showed, which
trap was found, what turned out not to work. Not "did X, then Y": the transcript
already has that, and it is the part worth least.

Append when something is learned rather than at fixed intervals, and always when:

- an approach was rejected, with why — this is the single most expensive thing to lose;
- a measurement produced a number;
- a trap was found that will bite the next person;
- a skill or document being filled in along the way gained a new point. It goes here,
  not into the live document: editing the document mid-task is expensive, and at
  handover the journal is edited into it in one focused step.

`hooks/note-bookkeeping.sh` counts edits since the journal was last written and puts a
nudge in the queue when the debt crosses a threshold. Answer it by appending, not by
promising to append later.

If the journal was lost anyway, `scripts/journal-from-transcript.sh` pulls the edited
paths and the commands out of the session transcript into a skeleton. It recovers what
was done, never why, so it is the floor and not a substitute.

## The snapshot

`context.md` answers, for someone arriving with an empty context:

- what is being done now;
- which decisions were taken, and why;
- what is still open;
- which measurements exist and where their raw data is;
- the next concrete step.

Rewritten in place. There is no rotation and no timestamped copies: the folder is the
task, the journal already holds how it got here, and ten old snapshots beside it were
read by nobody.

## One task, one pair of files

Both files live in `tmp/work/<task>/`, so two sessions working on two tasks in the same
repository do not overwrite each other. There is no repository-wide context file, and
the session banner names the active tasks instead.

## Promotion out of it

Anything that has become a **stable decision** is promoted into the repository's
permanent documents: its `AGENTS.md`, `README.md`, design docs. Both files are staging
areas. If durable facts accumulate there instead, the public documents stay empty and
the real state of the project becomes untransferable.

## Two properties worth remembering

`tmp/` is not tracked by git, so a clone does not carry it. Moving the work to another
machine, or restoring it from a backup, means copying `tmp/` as a separate step.

Some knowledge sits better in the agent's own memory than in a file. The test is
whether it survives a change of tool, and whether a person without an agent needs it.
If both, it goes in a file.
