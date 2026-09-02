*English · [Русский](idea.ru.md)*

---
type: idea
status: proposed
date: <YYYY-MM-DD>
---

# <what is being proposed>

The frontmatter is what makes this file readable once it has left `ideas/`. In the
archive there is no directory left to say what happened to it, so these fields are the
whole record, and they are what a `grep` finds when the same proposal comes back.

`type` is `idea`, `research` or `audit`; an audit also carries `model:` naming the
model that wrote it. `status` is `proposed`, `accepted` or `rejected`. Accepted adds
`work:` with the task's name and `closed:` with the date; rejected adds `closed:` and
`reason:` in one line.

## What this is about

The question or the problem, a few lines. Where it came from: a tray item, something
noticed while doing other work, a request in chat.

## What was found

The substance. Measurements with their numbers, approaches with what each costs,
extracts with where they came from. Attachments go in a folder of the same name beside
this file, never in the root of `tmp/`.

## What is proposed

Concrete enough to become a spec. Where there are several options, name the recommended
one rather than leaving a survey.

## What speaks against it

The costs, the risks, what stops working. An idea presented without this gets accepted
on enthusiasm and dismantled later.
