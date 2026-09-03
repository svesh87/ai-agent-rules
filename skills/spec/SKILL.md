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

`tmp/work/<YYYY-MM-DD>-<slug>/spec.md`. The slug is two or three words that read as a
name in `ls`. The folder is the task; every other file of it lands beside this one.

`scripts/task.sh new <slug> [--lang ru|en]` lays it out: the folder under today's date,
`spec.md` and `journal.md` from the templates, and nothing else yet. Find the script by
resolving the entry point, `readlink -f ~/.claude/CLAUDE.md` or
`readlink -f ~/.codex/AGENTS.md`, and looking in `scripts/` beside it; the templates are
in `templates/work/` there, for reading rather than copying by hand.

It strips the template's first line, and that is not a nicety. The line is the language
switch between the two copies of the template itself, so an instance carrying it points
at a template rather than at a translation of itself. An agent copied it into all four
files of a real task, adjusting the relative path as it went.

The spec is written in the language of the chat. The owner is the one who approves it
and it never reaches git.

## Measure before writing it

Where the unknown is what to build, a spec written first is the right document. Where
the unknown is how something behaves — a runtime, a payload, a tool's contract, a
production system — a spec written first is a guess, and two approvals over a guess turn
a cheap probe into a documented commitment. That is not hypothetical: a task in this
repository wrote its spec from a schema read out of a binary, and one live probe by the
owner overturned the conclusion the whole plan rested on.

So the measurement comes first and goes into `journal.md`, which the scaffolding creates
alongside the spec for exactly this. Then the spec, written against what was measured
rather than against what seemed likely. Sometimes the measurement shows there is no task,
and then no spec is written at all.

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

Record the approval where a check can see it: `scripts/task.sh approve spec` writes a
dated line into `.approvals` and stamps the status line. Until that line exists the
script refuses to create `plan.md`, because a plan written against an unapproved spec is
the first of the two approvals quietly skipped.

Then write `plan.md` with the `plan` skill — `task.sh new --plan` puts the template in
place — and `tasks.md` from the approved plan, not before it.

**An approved spec is not edited to match what was built.** Where the work turns out
smaller, larger or different, the new scope goes to the owner in chat and comes back as
a re-approval: `task.sh approve spec` again, with the reason in the journal. A spec
quietly brought into line with the code afterwards is a report wearing a spec's name,
and `task.sh check` reports it by comparing the file's mtime against its approval.
