*English · [Русский](plan.ru.md)*

# Plan: <what the work is>

**Status:** draft, awaiting the owner's approval
**Date:** <YYYY-MM-DD>
**Spec:** `spec.md` in this folder

The first word of the status is what a check can act on: `draft`, `approved` or `done`,
and free text after it. `scripts/task.sh approve plan` is what writes that word.

## Settled decisions

Answers the owner gave in chat, one line each. Decisions, not questions: a plan has no
questions section, and if a question is still open the plan is not ready.

- <fork> -> <what was decided>

## Default choices

Minor calls made without asking. Change any of them at review with one sentence.

- <choice> -> <what was done and why>

## Steps

1. **Code.** <files and what changes in them>
2. **Documentation and code comments.** Name the file plus anchor for every comment
   this change makes stale, rather than writing "update comments". Doc blocks and
   comments on constants go stale first and go stale silently.
3. **Gates.** <the repository's own commands; where it has no tests or linters, say
   what will be checked instead>
4. **Status edits.** Figures and statuses go in only after the gates confirm them.
5. **Consistency pass.** grep for terminology from the superseded model; grep for
   references to `tmp/` from the committed part; check each claim in the root
   documents against the code that implements it; terminology uniform; every
   translated copy against its original; `git diff --check`. If this step touched
   code, rerun the gates in full.
6. **A run in the other tool**, where the work has to hold in both. Claude Code and
   Codex differ in the skills directory, the hook registration and what the payload
   carries, and each of those differences was found by running something rather than
   by reading. Say what is asked of it and what counts as a failure of the work rather
   than of the report.

## What this plan does not do

The boundary that keeps scope from drifting mid-work: uncommitted work in the tree,
neighbouring repositories, anything not being installed, anything not being committed.

- <not this>

## For the owner

Checks nobody else can run. Listed so they are not forgotten, not to be raised again
later.

- <check>

## Result

Filled in after the work, never before: what was done, what was skipped and why, which
gates ran and what they reported. If something failed, its output goes here rather than
a summary of it.
