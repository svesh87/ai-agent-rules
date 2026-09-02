*English · [Русский](RATIONALE.ru.md)*

# Why these rules

[AGENTS.md](../AGENTS.md) is the imperative: one line per rule, so that a rule still
reads as an instruction at the end of a long session rather than as background prose.
The explanations came out of it and live here. No agent reads this file. It is for the
person deciding whether a rule should exist.

## Why the imperative and the reasoning are separated at all

A rule fires when it has an observable trigger and a stated action. "Comments explain
constraints, not the history of edits" has no moment of application; "before handing
over, grep for edit-history residue" has one. When a paragraph mixes the command with
the reason for it, what survives to the end of a session is the mood of the paragraph,
not the command.

The second reason is volume. Every line in an always-loaded file competes with every
other line for attention, and the file is paid for in every session of every project.
A rule that has never once been needed is not free; it lowers the odds that the rest
fire.

## Duplication between this file and repositories

This canon exists because rules are not everywhere. A repository may be new, may belong
to someone else, or may simply have no rules file, and an agent's first run in it still
has to know how the owner prefers to work.

So a repetition in a file that goes to git is not duplication when other developers or
their agents see the repository: they have no copy of this canon, and a rule known only
to one machine does not exist for them. Trimming makes sense only where the repetition
serves nobody, which is a private repository with a single user and a word-for-word
copy. A repetition that has drifted, the same rule with a changed meaning, is worse than
either a duplicate or no rule at all, because nobody can tell which version applies.

The decision is made per repository, the first time its rules are touched, alongside the
rest of the work there. Sweeping through every repository at once produces a large diff
nobody reviews.

## Why plans, and why so many questions before them

A question during planning costs a minute. A question during implementation costs the
work already done on a wrong assumption, plus the owner's attention at the moment they
had handed the task off. That asymmetry is the whole argument for asking a lot up front
and for the rule that a plan contains no questions section: an unanswered question means
the plan is not ready to be approved.

The plan lives in `tmp/` and not in git because it is correspondence about work, not a
document of the project. It is written in the language of the chat for the same reason:
the owner is its only reader.

There are two approvals rather than one because they answer different questions and fail
differently. A plan approved on its steps carries an unstated idea of what "done" means,
and the disagreement about that surfaces after the work rather than before it. So the
spec is approved first — what is being built, why, how done is measured, what counts as
delivered — and the plan is written against it. The cost is one extra round trip on
anything larger than an edit, which is why the size of the work decides the ceremony:
two lines get neither document.

Declaring the deliverables in the spec, secondary ones included, exists for a specific
failure. Work that is not the task itself loses to the task every time: a skill to be
filled in along the way, a document, a note in the rules. Named in the spec, it is
something handover can refuse to sign off on; left in the conversation, it is something
the owner has to remember, and the whole point of these rules is to remember less.

## Why `tmp/`

Two properties, both about loss. Findings that exist only in a conversation are gone
when the conversation ends, and a context that is summarised loses exactly the details
that were expensive to obtain. Writing them to files makes them survive a compaction, a
crash, and a change of tool.

And they must not reach git, because a draft plan committed to a repository becomes a
requirement to whoever reads it next. The machine-wide ignore does that job in every
repository at once, including ones that do not belong to the operator, which is why the
patterns live there rather than in each `.gitignore`.

The three genres came later, from what the directory actually looked like after a few
months: thirteen to twenty-one files loose in the root of seven repositories, up to
forty-one in the archive, plans and snapshots and probe binaries and screenshots in one
heap. The problem was not tidiness. Nothing recorded which task a file belonged to, so a
plan and a snapshot written the same evening about the same work could only be connected
by opening both, and nothing recorded whether a file was finished, so a rejected proposal
and a live one looked identical. A file that cannot be attributed cannot be found later,
and a file with no end state cannot be thrown away — which is how cleaning up became a
thing the owner had to ask for.

Hence: a task is a folder, so everything about it stays together and archives in one
move; an idea is a file with a status, so a proposal has somewhere to live and two ways
to end; an artefact belongs to one of those and never to the root. The tray is separate
from all three because catching a thought has to cost nothing, and a tray item with a
body is an idea that has not been moved yet.

Nothing here is converted from the old layout. A plan from last month has no spec, and
writing one for it means inventing requirements the work never had; a dead document
dressed as a current one is worse than a heap that honestly looks like a heap.

The state of the work is split in two for a reason that is about cost, not tidiness.
There used to be one snapshot per repository, rewritten in full each time and rotated
into `tmp/old/` with a timestamp. Rewriting it was expensive, so it was deferred, and
the deferral routinely ran past the end of the context window — the one place where
deferring loses everything. So `journal.md` is appended to and never rewritten, which
makes it cheap enough to actually happen, and `context.md` is rewritten once at
handover. Both live in the task's folder, which also ends two sessions in one repository
overwriting each other's state.

## Why signing and the hardware key get their own rules

A signature is a claim about who made a change. Turning signing off to get past a
timeout converts an inconvenience into a false claim, silently, and the commit looks
normal afterwards. Hence: never `--no-gpg-sign`, and a single retry before handing the
ready command back.

The waiting rules exist because a token prompt looks exactly like a hung process. An
agent that kills it "to try something else" makes the operator repeat the physical
touch, and does it repeatedly if the rule is not explicit.

## Why nothing leaves on its own

Sending a message, filing an issue, deploying: these are the actions where a mistake
cannot be corrected by an edit. The person whose name is on the outgoing message is the
one who presses the button. A draft costs seconds and makes the mistake visible while it
is still cheap.

The same logic covers what has already gone out. Regenerating a signed document or
refiling a report produces two versions of a thing that was supposed to have one, and
the discrepancy usually surfaces at the worst possible moment.

## Why personal data is graded by repository, not banned outright

A production configuration needs real names to work. Pretending otherwise produces
either a broken configuration or a second, secret copy of it. So real data is allowed
exactly where it is functionally necessary, in a private repository, and nowhere else:
tests, fixtures, examples and documentation take invented names, because that is where
data leaks from without anyone noticing.

A public repository is the one place where the rule is absolute, and it extends past
names to host names, absolute paths from a developer's machine, and stories about
incidents. Those are the details that turn a code sample into an intelligence report
about an employer.

## Why edits go through an editor

The rule is not about aesthetics. A change made by piping a file through a script does
not appear as a reviewable diff, and a replace against a file whose content has shifted
edits the wrong thing without saying so. Both failures are silent, and silence is the
expensive part.

This is also the most-broken rule in the set, by a wide margin, which is why it is now a
hook rather than a sentence. The measurement is in
[mechanisms.md](mechanisms.md).

## Why hooks and skills instead of more text

Three levels of reliability, in order. The harness executes a hook, so it does not
depend on the model noticing anything: this is the only level that holds regardless of
session length. A skill arrives at the moment of work and carries its detail with it,
which is close to reliable but still depends on the skill being selected. Always-loaded
text is the weakest level, and it gets weaker as the session grows.

A rule broken twice therefore moves up a level rather than being restated more firmly.
Restating it louder is the response that feels productive and measurably does not work.

The cost is that a hook can be wrong, and a hook that wrongly blocks an editing tool
takes away the means to fix itself. Hence the properties asserted first in the selftest:
an editing tool inside the work tree is never blocked, and an unparseable payload is
allowed rather than denied.

## Why the repository category is computed rather than remembered

Eight categories, from a local directory with no remote to someone else's repository
with its own rules, and each one permits a different set of actions. Applying that from
memory means getting it wrong occasionally in the direction that cannot be undone: a
push into a foreign repository, rules committed where they must not be, personal data in
something public.

The signals are all local and cheap: whether there is a remote, which host and namespace
it points at, whether a rules file is tracked, and who first authored it. Authorship is
the one that matters most in a work repository, because a rules file I wrote is mine to
edit and a colleague's is not, and both look identical in a directory listing.

Which hosts and accounts are the operator's own is deliberately not in this repository.
It is personal, this repository is public, and the classifier reads it from a file
outside git. Without that file every unknown remote counts as foreign, which is the
strict answer.

## Why subagents get their own rule

A subagent starts with an empty context and pays full price for its briefing, while the
main loop reads the same material from a warm cache. That makes delegation an economic
question rather than a stylistic one: it pays when the work is large relative to the
briefing, and loses when it is not.

It also means everything not written in the task text does not exist for the subagent.
Rules that must hold for delegated work go into the briefing or into a skill the
subagent is told to read, because it will never see the canon.
