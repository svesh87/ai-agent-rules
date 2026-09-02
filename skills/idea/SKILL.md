---
name: idea
description: Research, a proposal for review, an audit, a finding noticed in passing — write it where it can be found again and closed. Triggers: "проведи ресёрч", "предложи на ревью", "изучи вопрос", an audit, a finding that is not this task's work, a tray item being picked up that needs a body.
---

# Ideas, research and proposals for review

Everything that is a proposal rather than work belongs to one genre with one lifecycle.
Research, a comparison of approaches, an audit, a finding noticed while doing something
else, an item from the tray that outgrew its two lines: all of them are ideas.

The genre exists because proposals used to have no place. They landed in the root of
`tmp/` under invented names, could not be found a week later, and had no end state, so
a rejected proposal and an accepted one looked exactly alike.

## Where it goes

`tmp/ideas/<YYYY-MM-DD>-<slug>.md`. It becomes a folder of the same name with
`idea.md` inside only when it needs attachments — measurements, probes, extracts —
which then live beside it rather than in the root of `tmp/`.

The date comes from `date '+%Y-%m-%d'`. The shape is in `templates/idea.md`, or
`idea.ru.md` for Russian; find them beside the resolved entry point, as the `spec`
skill describes. The template's first line is the language switch between the two copies
of the template itself: it is not part of the shape and is not copied into the idea.

## The frontmatter is the part that matters

```yaml
---
type: idea | research | audit
status: proposed | accepted | rejected
date: 2026-09-02
model: opus5              # audits only, the model that wrote it
work: 2026-09-02-slug     # accepted only, the task it became
closed: 2026-09-05        # accepted or rejected
reason: one line          # rejected only
---
```

The fields are what makes an idea readable once it has left `ideas/`. In the archive
there is no directory left to say what happened to it, so `status`, `closed` and
`reason` are the whole record — and they are what `grep -r 'status: rejected'` finds
when the same proposal comes back in three months.

There is no index of `tmp/` and none is to be built. While an idea is live, its
directory says it is open, its filename says when and about what, and `ls` costs
nothing. A generated index would repeat all three and go stale between runs.

## Two end states, and neither is silence

**Accepted**: `status: accepted`, `work:` naming the task it became, `closed:` dated.
The spec of that task links back. Then the file goes to `tmp/archive/<YYYY-MM>/`.

**Rejected**: `status: rejected`, `closed:` dated, `reason:` in one line. Then the same
archive. The reason is the whole point: without it the same proposal comes back in
three months and is researched again from scratch.

An idea nobody has decided on stays `proposed` and stays in `tmp/ideas/`. That is
legitimate, and the session banner will eventually say how long it has been sitting
there. Nothing is closed to tidy up the directory.

## Its relation to the tray

`tmp/TODO.md` is the intake tray, and catching a thought there costs one line and
touches nothing else — including into a neighbouring repository, which is the case the
write-scope hook lets through without a question. An idea is where that thought lives
once someone starts working it out.

So the two are stages, not alternatives, and the move happens at the second stage. Do
not create an idea file while capturing: writing one is ceremony, and capture is the one
operation in this scheme that has to stay free. When the item is next picked up, and
only then, it becomes a task, gets rejected in one line, or grows a body and moves here
with the tray keeping a line pointing at it. When the idea reaches an end state, the
tray item stops being open in the same edit.

## Research that was asked for in chat

A request to research something and come back with proposals produces an idea file, not
a chat answer that evaporates. Brief in chat, in full in the file. The chat summary is
what the owner reads to decide; the file is what survives the session.

## Audits

An audit is an idea with `type: audit` and the model that wrote it in `model:`. Before
writing a new one, move previous audits **from the same model** to the archive.

Leave other models' audits alone. They are evidence, not clutter.

## What is not a finding

"Add protection for the future." "Consider making this extensible." "Might be worth
adding tests here" without saying which behaviour is unverified. A finding names what
breaks, with the input or the state that breaks it.

Before proposing machinery against a hypothetical state, ask the owner whether that
state exists at all. One question is cheaper than surplus code plus tests plus
documentation plus its eventual removal.

## Turning someone else's proposal into work

Every finding is checked against the code before it enters a spec. An audit, a review,
text pasted into chat: all outside remarks, and outside remarks are not copied
unexamined. A finding that does not reproduce is written off explicitly, with the
reason, rather than silently dropped.

Read the current state again before auditing rather than taking it from memory or from
an earlier snapshot. A document describing what the code did last month is a finding in
itself.
