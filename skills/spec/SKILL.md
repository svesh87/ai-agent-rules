---
name: spec
description: Write the spec of a task, the first of its two approvals. Triggers: work larger than a couple of edits, "давай спеку", "составь план" (the spec comes first), a request whose acceptance is not yet agreed, an idea that has just been accepted.
---

# The spec, before the plan

A task is approved twice. The spec is the first approval and answers what is being
built, why, and how done is measured. How it will be built belongs in `plan.md` and is
written only after this one is agreed.

Splitting them is not ceremony. A plan written against an unstated acceptance gets
approved on its steps, and the disagreement about what "done" meant surfaces after the
work.

## Where it goes

`tmp/work/<YYYY-MM-DD>-<slug>/spec.md`. The date comes from `date '+%Y-%m-%d'`, the
slug is two or three words that read as a name in `ls`. The folder is the task; every
other file of it lands beside this one.

Take the shape from `templates/work/spec.md`, or `spec.ru.md` for Russian. Find the
templates by resolving the entry point, `readlink -f ~/.claude/CLAUDE.md` or
`readlink -f ~/.codex/AGENTS.md`, and looking in `templates/` beside it.

The template's first line is the language switch between the two copies of the template
itself. It is not part of the shape and is not copied: a task has one language, and an
instance carrying that line points at a template rather than at a translation of itself.
An agent did copy it, adjusting the relative path, which is how this sentence came to be
here.

The spec is written in the language of the chat. The owner is the one who approves it
and it never reaches git.

## What goes in it

- **Why.** The problem, not the solution. Where the reason is a defect, what it does;
  where it is a request, what the owner asked for. Where there are measurements, the
  numbers, because a spec whose "why" is an impression gets argued about later.
- **What we are doing.** The boundaries, a few lines. Implementation belongs to the
  plan; here it is only enough to tell what is in scope from what is out.
- **Acceptance.** Criteria that can be checked, one per line. "The banner names the
  active tasks" can be checked; "the scheme works" cannot. This is the section the plan
  is later written against, so an unmeasurable line here becomes an argument later.
- **Deliverables.** The main one, and every secondary one by name: a skill to be filled
  in along the way, a document, a change to the rules. Declaring them is what lets
  handover refuse to call the work done while one is untouched, and what stops the owner
  from having to remember them.
- **For the owner.** Checks nobody else can run: live hardware, a production system, a
  device, another tool's session.

## What does not go in it

No steps, no file lists, no commands: that is the plan, and a spec that contains it
gets approved as a plan by accident.

No questions section. Genuine forks — architecture, scope, external configuration,
anything where two readings lead to materially different work — go to the owner in chat
**before** the spec is finalised, and their answers come back into it as settled
decisions. If a question is still open, the spec is not ready.

Ask a lot at this stage, and ask about everything that affects the result rather than
only the large things.

## Where a spec comes from

Usually from an idea that has been accepted, or from an item in `tmp/TODO.md`. Either
way the source is closed as part of writing this: the idea gets `status: accepted` and
the task's name, the tray item stops being open. See the `idea` skill.

Brownfield work needs one extra sentence of honesty: where the spec is reconstructed
from existing code, say which parts are read off the code and which are assumed. A
reconstructed spec presented as a given is the same failure as converting an old plan
into a task.

## After it is approved

Write `plan.md` with the `plan` skill, then `tasks.md` from the approved plan. Not
before: a task list built ahead of the plan gets rewritten the moment the plan changes.
