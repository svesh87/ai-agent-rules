---
name: plan
description: Write or revise the plan of a task, the second of its two approvals. Triggers: an approved spec, "давай план", "составь план", a plan revised after review, an unforeseen fork mid-work.
---

# The plan, against an approved spec

The plan is the second approval and answers how. What is being built and how done is
measured is the spec's job; if there is no approved spec yet, write that first with the
`spec` skill.

Execution begins on an explicit instruction, not on the owner reading the plan and
saying nothing.

## Where it goes

`tmp/work/<YYYY-MM-DD>-<slug>/plan.md`, beside the spec it belongs to. The task is the
folder, and everything of it stays inside: `tasks.md`, `journal.md`, `context.md`, and
`research/` and `artifacts/` for what the work produces.

`scripts/task.sh new --plan` puts the template in place, in the task's language, without
the template's first line — that line is the language switch between the two copies of
the template itself and belongs to neither instance. The script refuses while the spec
carries no approval in `.approvals`: the plan is the second approval, and one written
against an unapproved spec has skipped the first. Do not invent a structure and do not
copy one from another repository.

The plan is written in the language of the chat, not of the repository. The owner is
the one who reads it, and it never reaches git.

A superseded plan is replaced in place, not accumulated: the folder holds one plan, and
the version that matters is the current one. Nobody reads the history of a plan's
edits; what is read is the plan plus its result.

## Its shape

- **Settled decisions**: the answers the owner gave in chat, one line each. Decisions,
  not questions. A plan has no questions section, and if a question is still open the
  plan is not ready.
- **Default choices**: minor calls made without asking, each changeable at review.
- **Steps**, in the order handover uses them.
- **What this plan does not do**: the boundary that stops scope from drifting during
  execution. Uncommitted work in the tree, neighbouring repositories, anything not
  being installed.
- **For the owner**: checks nobody else can run.
- **Result**: filled in after the work, never before.

## What the steps must contain

- **Code**: files and what changes in them.
- **Documentation and code comments**: for every comment this change makes stale, the
  file and the anchor. Not a line saying "update comments". Doc blocks and comments on
  constants go stale first and go stale silently, because neither tests nor gates see
  them.
- **Gates**: the actual commands of this repository. If it has no tests or linters, say
  what is checked instead. Never propose introducing them on your own initiative.
- **Status edits**: figures and statuses only after the gates confirm them.
- **A consistency pass, last**: see the `handover` skill for its minimum scope.

Where the work has to hold in both tools, a run in the other one is a step of its own
with its own pass criteria. Claude Code and Codex differ in ways that only show up when
something is actually run: the skills directory, the hook registration, what the
payload carries.

## Three sizes, and only one of them gets this

An edit of a couple of lines starts nothing: no folder, no spec, no plan. A task gets
the folder and both approvals. An epic gets a roadmap over several specs, and only when
the owner asks for one — a roadmap passes through no check of its own, so a wrong one
sends every spec under it in the same wrong direction, neatly and consistently.

## After it is approved

`scripts/task.sh approve plan` records the owner's yes as a dated line and stamps the
status, and only then does `task.sh new --tasks` lay out `tasks.md`: a checklist built
ahead of the plan gets rewritten the moment the plan changes.

The approvals file is bookkeeping, not a boundary — the agent runs the script, so the
agent could write the line unasked. What it buys is that the approval exists as a dated
record rather than as somebody's memory of the chat, and that the status line has a
single author and cannot drift away from it. Its checkboxes are ticked as the
work goes, and they record progress only — reasons, measurements and traps go into
`journal.md`.

## While executing it

An unforeseen fork means stop and ask, unless you can answer it yourself from the code,
the data or the live state, in which case look first and ask afterwards.

Outside remarks — an audit, a review, text pasted into chat — are not copied into a
plan unexamined. Check every finding against the code first. "Add protection or
extensibility for the future" is not a finding.

The owner's "no" holds until they return to the subject themselves.
