---
name: context-snapshot
description: Write or refresh tmp/CONTEXT.md, the snapshot of where the work stands. Triggers: end of an iteration, handing work back, compaction ahead, "сохрани контекст", "зафиксируй состояние".
---

# The snapshot of the current state

`tmp/CONTEXT.md` is a snapshot, not a log. It answers, for someone arriving with an
empty context:

- what is being done now;
- which decisions were taken, and why;
- what is still open;
- which measurements exist and where their raw data is;
- the next concrete step.

Everything that is not yet a settled decision lives in files under `tmp/`, never only
in a conversation. A session that ends with its findings in chat has lost them.

## Rotating it

Rewrite it at the end of an iteration and before handing work back. The previous
version moves to `tmp/old/` with a timestamp in its name, it is not appended to and
not deleted.

## Promotion out of it

Anything in the snapshot that has become a **stable decision** is promoted into the
repository's permanent documents: its `AGENTS.md`, `README.md`, design docs. The
snapshot is a staging area. If durable facts accumulate there instead, the public
documents stay empty and the real state of the project becomes untransferable.

## What it is not

Not a diary of what happened in which order. Not a copy of the plan. Not a place for
anything that belongs in the repository's own documents.

## Two properties worth remembering

`tmp/` is not tracked by git, so a clone does not carry it. Moving the work to another
machine, or restoring it from a backup, means copying `tmp/` as a separate step.

Some knowledge sits better in the agent's own memory than in a file. The test is
whether it survives a change of tool, and whether a person without an agent needs it.
If both, it goes in a file.
