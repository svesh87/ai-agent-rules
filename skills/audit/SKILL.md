---
name: audit
description: Audit a repository or a change, or turn someone else's audit into work. Triggers: "сделай аудит", "проверь код", a review of the whole thing, combining findings from several models. Covers naming, rotation, what counts as a finding.
---

# Audits

## Where they go

An audit goes to `tmp/AUDIT_<AI_MODEL>_<YYYY-MM-DD_HH-MM-SS>.md`, with the model that
wrote it in the name. Before writing a new one, move previous audits **from the same
model** to `tmp/old/`.

Leave other models' audits alone. They are evidence, not clutter.

A combined audit is assembled into `tmp/AUDIT_SUM_<date_time>.md` from recent audits by
different models, less than an hour old, so they describe the same code. Previous
`AUDIT_SUM_*` files move to `tmp/old/`.

## What an audit looks for

Simplicity, resistance to speculative extensibility, absence of surplus robustness.
Concretely: machinery built for a state that does not exist, compatibility with formats
nothing writes, defences against situations the system cannot reach, abstraction with
one implementation.

## What is not a finding

"Add protection for the future." "Consider making this extensible." "Might be worth
adding tests here" without saying which behaviour is unverified. A finding names what
breaks, with the input or the state that breaks it.

Before building machinery against a hypothetical state, ask the owner whether that
state exists at all. One question is cheaper than surplus code plus tests plus
documentation plus its eventual removal.

## Turning someone else's audit into work

Every finding is checked against the code before it enters a plan. An audit is an
outside remark, and outside remarks are not copied into plans unexamined. A finding
that does not reproduce is written off explicitly, with the reason, rather than
silently dropped.

## The live state outranks the documentation

Read the current state again before auditing rather than taking it from memory or from
an earlier snapshot. A document describing what the code did last month is a finding in
itself.
