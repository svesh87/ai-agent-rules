---
name: plan
description: Write or revise a work plan in the shape this operator expects. Triggers: work larger than a couple of edits, "давай план", "составь план", a plan revised after review, an unforeseen fork mid-work.
---

# A plan, before the work

Non-trivial work starts with a draft plan and waits. Execution begins on an explicit
instruction, not on the owner reading the plan and saying nothing.

## Where it goes

`tmp/FIX_PLAN_<YYYY-MM-DD_HH-MM-SS>.md` at the root of the working directory. Get the
timestamp from `date '+%Y-%m-%d_%H-%M-%S'`, do not invent one.

`tmp/` is never committed. When a previous plan is superseded, move it to `tmp/old/`
and leave the current one in place until the next appears. Plans for later cycles that
are already drafted go to `tmp/DRAFT_PLAN_<n>.md` so they survive context compaction.

If `tmp/` already exists and belongs to the project rather than to agent work, keep
yours separate and ask where drafts should go.

## Its shape

Take the template from this repository: `templates/plan.md` in English,
`templates/plan.ru.md` in Russian. Find them by resolving the entry point,
`readlink -f ~/.claude/CLAUDE.md` or `readlink -f ~/.codex/AGENTS.md`, and looking in
`templates/` beside it. Do not invent a structure and do not copy one from another
repository.

The plan is written in the language of the chat, not of the repository. The owner is
the one who reads it, and it never reaches git. This is the single exception to the
rule about the language of files.

## Forks go to the owner first

Genuine forks — architecture, scope, external configuration, anything where two
readings lead to materially different work — are raised in chat **before** the plan is
finalised. The answers are then written into the plan as settled decisions.

A plan has no "questions" section. If a question is still open, the plan is not ready.

Ask a lot at this stage, and ask everything that affects the result rather than only
the large things. Wearing the owner out during preparation is cheap; interrupting them
mid-implementation is not.

Minor choices made without asking go in a "default decisions" section, each marked as
changeable at review.

## What the steps must contain

- **Code**: files and what changes in them.
- **Documentation and code comments**: for every comment this change makes stale, the
  file and the anchor. Not a line saying "update comments". Doc blocks and comments on
  constants go stale first and go stale silently, because neither tests nor gates see
  them.
- **Gates**: the actual commands of this repository. If it has no tests or linters,
  say what is checked instead. Never propose introducing them on your own initiative.
- **Status edits**: figures and statuses only after the gates confirm them.
- **A consistency pass, last**: see the `handover` skill for its minimum scope.

Checks only the owner can perform — live hardware, a production system, a physical
device — go in a section of their own so they are not lost, and are not raised again
afterwards.

## While executing it

An unforeseen fork means stop and ask, unless you can answer it yourself from the
code, the data or the live state, in which case look first and ask afterwards.

Outside remarks — an audit, a review, text pasted into chat — are not copied into a
plan unexamined. Check every finding against the code first. "Add protection or
extensibility for the future" is not a finding.

The owner's "no" holds until they return to the subject themselves.
