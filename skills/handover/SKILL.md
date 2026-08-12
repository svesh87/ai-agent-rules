---
name: handover
description: Finish work before handing it back: order of edits, gates, consistency pass, what to report. Triggers: "сдавай", "готово?", "прогони гейты", coverage or tests in play, about to call something done.
---

# Handing work over

## The order

1. Code.
2. Documentation and code comments.
3. Gates.
4. Status edits: figures and statuses only **after** the gates confirm them.
5. Consistency pass, last.
6. Refresh the working context (see the `context-snapshot` skill).

Code comments are a work item like any document, with their own step and a list of
file plus anchor. Doc blocks and comments on constants go stale first and silently.

## The gates

In a repository that has tests and linters, before handing work over:

- the linter is clean;
- the tests are green;
- line coverage of production code is at 80% or above, or higher if the repository
  names its own threshold;
- the build passes;
- `git diff --check` is clean.

Run the full suite after every coherent iteration, not only at the end.

Work is not finished while a test fails, is skipped unexpectedly, is flaky, or
coverage is below the threshold.

In a repository without tests and linters, do not introduce them on your own
initiative. Run checks when the owner asks, and where the work plainly calls for one,
offer it in chat. In a foreign repository, do not run their suite unasked at all.

## What the gates are not

They are not to be worked around. Do not weaken assertions, do not delete tests, do
not exclude production files from coverage, do not mark tests as expected failures.
Every fixed defect gets a regression test where the repository has tests.

## The consistency pass

Minimum scope, and it is the last step:

- grep for terminology from a superseded model or a previous naming;
- grep for edit-history residue in code and docs: "used to", "now", "no longer",
  "replaced by";
- grep for references to `tmp/` from the committed part: there must be none;
- check every claim in the root documents against the code that implements it, paths,
  thresholds, units, partial-failure and restart behaviour included;
- every translated copy against its original, by meaning (see the `translate` skill);
- terminology uniform across documents and languages;
- `git diff --check`.

If the pass touched code, rerun the gates in full.

## Before saying it is done

Check your own text for the marks of machine-generated writing: an em dash where a
comma or a colon would do, "not just X, but Y", triples for the symmetry of it, "it is
important to note", "in conclusion", a closing paragraph that summarises and adds
nothing, marketing vocabulary, emoji in headings, bold every other sentence. Nothing
written into a file carries profanity or conversational licence, whatever the chat
sounds like.

## Reporting

Report what actually happened: what was done, what was skipped and why. When a script
fails, show its output rather than a summary of it.

Never claim that something was verified on live hardware, on a device, on a server or
in an interface if that verification did not happen. Keep confirmed state and
assumption apart, and say which is which.

When the work is done, list the changed files, show `git status`, and stop. Do not
offer to commit, build or deploy: the owner keeps that cycle to themselves.

## Before stopping for review

Move out of the context and into files whatever would be lost with it: decisions,
inventories, traps discovered, changes to the procedure. The measure is that an agent
starting tomorrow with an empty context can rebuild the picture from the files. This
means writing files, not committing.
