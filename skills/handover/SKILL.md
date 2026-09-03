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
6. Close the task (below).

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
- `scripts/task.sh check <task> --handover`: untouched deliverables, a spec edited after
  its approval, a status line that no longer matches the approvals, a template's language
  switch left at the top of a document, checkboxes still open;
- check every claim in the root documents against the code that implements it, paths,
  thresholds, units, partial-failure and restart behaviour included;
- every translated copy against its original, by meaning (see the `translate` skill);
- terminology uniform across documents and languages;
- `git diff --check`.

If the pass touched code, rerun the gates in full.

## Closing the task

Four steps, none of which the owner should have to ask for.

**Every declared deliverable is checked.** The spec named them, the secondary ones
included. A deliverable that is untouched means the work is not done, whatever the
gates say. `scripts/task.sh check` compares the paths in the spec against the working
tree; `hooks/stop-gates.sh` calls the same check on its own at the end of a turn, but the
step belongs here regardless of whether the hook spoke.

Where the answer is "not needed after all", that is a change of scope, not a note in the
report: it goes to the owner and comes back as a re-approved spec. The first two tasks
under this scheme both closed with declared deliverables untouched and the reason written
into the result instead.

**The journal is turned into what it was raw material for.** A skill or a document
being filled in along the way was appended to `journal.md` during the work; this is the
focused step where it is edited into shape. Skipping it is how the accumulated notes
stay notes.

**The source is closed.** The idea this task grew from gets `status: accepted` and the
task's name; the tray item in `tmp/TODO.md` stops being open. Nothing is closed
silently, and a rejection carries its reason in one line.

**The folder goes to the archive.** `context.md` is rewritten first (see the
`context-snapshot` skill), then the status lines of the spec and the plan are brought to
their end state: `task.sh check` reads a task in the archive that still says draft as a
finding, and both archived tasks of the first month went in saying exactly that. Then
the whole of `tmp/work/<task>/` moves to `tmp/archive/<YYYY-MM>/`, plan and journal
and probes together. The move is the whole
bookkeeping: `tmp/work/` holding only live tasks is what makes the layout readable, and
there is no index to update afterwards.

Work the owner has not accepted yet is not archived. A plan still waiting for approval,
or a task whose live checks are still outstanding, stays in `tmp/work/`.

## Before saying it is done

Check your own text for the marks of machine-generated writing: an em dash where a
comma or a colon would do, "not just X, but Y", triples for the symmetry of it, "it is
important to note", "in conclusion", a closing paragraph that summarises and adds
nothing, marketing vocabulary, emoji in headings, bold every other sentence.

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

By this point most of it should already be in `journal.md`, appended as it happened. A
handover that has to reconstruct the whole session from memory means the saving was
deferred, which is the failure the journal exists to prevent.
