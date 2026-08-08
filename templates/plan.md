*English · [Русский](plan.ru.md)*

# <what the work is>

**Status:** draft, awaiting the owner's approval
**Date:** <YYYY-MM-DD>

## Why

One paragraph on the problem, not on the solution. If the reason is a defect, say
what it does; if it is a request, say what the owner asked for.

## Settled decisions

Answers the owner gave in chat before this plan was written, one line each. These
are decisions, not questions, and there is no section for questions in a plan.

- <fork> -> <what was decided>

## Default choices

Minor calls made without asking. Change any of them at review.

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

## For the owner

Checks nobody else can run: live hardware, a production system, a physical device.
Listed here so they are not forgotten, not to be raised again later.

- <check>

## Result

Filled in after the work, never before: what was done, what was skipped and why,
which gates ran and what they reported. If something failed, its output goes here
rather than a summary of it.
