*English · [Русский](spec.ru.md)*

# <what the work is>

**Status:** draft, awaiting the owner's approval
**Date:** <YYYY-MM-DD>
**From:** <the idea or tray item this grew out of, if any>

The first word of the status is what a check can act on: `draft`, `approved` or `done`,
and free text after it. `scripts/task.sh approve spec` is what writes that word, so the
line and `.approvals` have one author between them and cannot drift apart.

## Why

The problem, not the solution. If the reason is a defect, what it does; if it is a
request, what the owner asked for. Where there are measurements, the numbers.

## What we are doing

The boundaries, a few lines. No steps and no file lists: those are the plan's, and a
spec that carries them gets approved as a plan by accident.

## Settled decisions

Answers the owner gave in chat before this spec was written, one line each. These are
decisions, not questions, and there is no section for questions.

- <fork> -> <what was decided>

## Acceptance

Criteria that can be checked, one per line. "The banner names the active tasks" can be
checked; "the scheme works" cannot. The plan is written against this section, so a line
that cannot be measured becomes an argument later.

- <criterion>

## Deliverables

The main one, then every secondary one by name: a skill filled in along the way, a
document, a change to the rules. Handover refuses to call the work done while one of
these is untouched, so anything left out here is something nobody will chase.

- <path> — <what it must contain>

## For the owner

Checks nobody else can run: live hardware, a production system, a device, a session in
another tool.

- <check>
