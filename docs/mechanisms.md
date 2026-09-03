*English · [Русский](mechanisms.ru.md)*

# What each mechanism actually does

Measured on Claude Code 2.1.216 and Codex CLI 0.144.1 on 12 August 2026. Everything
below is either an experiment with its result, or a documented fact marked as such.
The distinction matters: half of what looked obvious from the names turned out to be
wrong, and the same trap is waiting for the next person.

## Where a rule can live, and what that costs

| Surface | Loaded | Cost in context | Survives a long session |
| --- | --- | --- | --- |
| `AGENTS.md` / `CLAUDE.md` | always, at session start | its full size, every session | poorly: it dilutes |
| `.claude/rules/*.md` | always | full size | same as above |
| nested `CLAUDE.md` | when working under that directory | full size, in that subtree | same as above |
| skill | name and description always, body on use | one line until used | well: it arrives at the moment of work |
| hook | never in context | nothing | perfectly: the harness runs it |

The measurement that drove this whole rearrangement: the rule "edits are made with an
editor, not through the shell" was broken 750 times against 452 times obeyed over three
days of transcripts. Split into sixths of a session, the share of shell edits goes 4%,
37%, 85%, 97%, 97%, 35% in one session and 21%, 63%, 63%, 71%, 100%, 88% in another,
while a short session of 891 lines stayed at 0-7% throughout. The breakdown starts well
before the first context compaction, so the cause is dilution of an instruction sitting
at the top of a growing context, not compaction losing it.

## What the task scheme actually enforces

The scheme of genres, two approvals and a journal was written as prose, and prose is
executed at the agent's discretion. The first two tasks written under it show what that
came to: one skipped the first approval and said so in its own spec, the other edited its
spec after the code was committed and moved half of its declared deliverables into a
section called "already delivered". Both went to the archive still carrying the status
line "draft, awaiting the owner's approval".

What runs without anybody remembering it, on the other hand:

| Mechanism | Where | What it catches |
| --- | --- | --- |
| bookkeeping debt | `hooks/note-bookkeeping.sh` | edits since `journal.md` was written, at 40 and 80 |
| staged creation | `scripts/task.sh new` | a plan before the spec is approved, a checklist before the plan is |
| approval as a record | `scripts/task.sh approve` | the status line and `.approvals` cannot disagree, because one author writes both |
| the state of a task | `scripts/task.sh check` | untouched deliverables, a spec edited after approval, a status that no longer matches, a template's language switch left in an instance, and at handover: checkboxes still open, a task with no spec at all |

`hooks/stop-gates.sh` is one of two entrances to the last of those; the `handover` skill
is the other, and it passes `--handover` to add the checkboxes, which mid-task are the
normal state rather than a finding.

`.approvals` is bookkeeping and not a boundary. The agent runs the script, so the agent
can write the line unasked — the same reason a terminal command minting a grant was
rejected for Codex in favour of the owner's own chat message. What the file buys is that
an approval exists as a dated record instead of somebody's memory of the conversation,
and that a check can compare the spec's mtime against it. Against an agent that lies it
buys nothing, and it is not meant to.

## Claude Code and Codex, surface by surface

| | Claude Code 2.1.216 | Codex 0.144.1 |
| --- | --- | --- |
| Always-loaded rules | `CLAUDE.md`, and `AGENTS.md` natively | `AGENTS.md`, `$CODEX_HOME/AGENTS.md` |
| Machine-local rules | `CLAUDE.local.md`, `AGENTS.local.md` | **not read at all** |
| Rules size limit | none | `project_doc_max_bytes`, default 32768 |
| Skills, global | `~/.claude/skills/<name>/SKILL.md` | `$CODEX_HOME/skills/<name>/SKILL.md` |
| Skills, per repository | `.claude/skills/` | `.codex/skills/` |
| Hooks | `hooks` in `~/.claude/settings.json` | `hooks.json` and `config.toml`, home and repository |
| Hook events in common | PreToolUse, PostToolUse, UserPromptSubmit, SessionStart, Stop, SubagentStop, PreCompact | the same, plus PermissionRequest, PostCompact, SubagentStart |
| Tool names in a payload | `Bash`, `Edit`, `Write` | `Bash`, `apply_patch`, and `Edit`/`Write` accepted as matchers |
| Deny a tool call | exit 2 with the reason on stderr, or `hookSpecificOutput.permissionDecision` | identical |
| Disabling MCP servers | `disabledMcpServers` per project in `~/.claude.json` | `enabled = false`, including in `<repo>/.codex/config.toml` |
| Turning off cloud connectors | `disableClaudeAiConnectors` | not applicable |
| Per-tool MCP disabling | none | `disabled_tools` per server |

The practical consequence: one set of hook scripts serves both tools, because the payload
field names and the deny contract are the same in both. Only the registration file
differs, which is why `registry/` holds two of them.

Two places do branch, and neither is about the payload. Both read `CLAUDECODE`, which a
Claude Code session exports into everything it runs. `hooks/session-start.sh` uses it to
inject the local rules file that Codex does not read, and `lib/payload.sh` uses it to pick
the delivery marker of the agent it is running under, because the queue directory is
shared between the agents and the `UserPromptSubmit` registrations are not. Anything that
is not a Claude session counts as the other case, which is the safe direction in both
places: a duplicated paragraph costs context, and a queued line nobody collects costs the
rule.

## Verified by experiment

**A skill inside a repository works in both, through a symlink.** Each tool reads only
its own directory: with `.claude/skills/probe-claude` and `.codex/skills/probe-codex`
side by side, Codex saw `probe-codex` and not the other, and Claude Code the reverse.
Both follow a symlink, so one canonical `skills/<name>` with `.claude/skills/<name>`
and `.codex/skills/<name>` pointing at it is seen by both.

**Codex loads repository skills without trust.** In a repository marked
`trust_level = "untrusted"`, `skills/list` returned the repository skill with
`scope: "repo"`, and Codex printed: project-local config, hooks and exec policies are
disabled until the project is trusted, but skills still load.

**A deny from PreToolUse really stops the call, in both tools, even in full auto.** With
`approval=never` (which reaches the hook as `permission_mode: "bypassPermissions"`),
both a shell command and an `apply_patch` were stopped before any side effect, and the
model received the refusal as an ordinary tool result. `exit 2` plus a reason on stderr
normalises to the same thing as the JSON form, which is why it is the contract used
here.

**An ask decision reaches the owner and their answer decides, in permission mode `auto`.**
A `Write` to a path outside the work tree was stopped by `hookSpecificOutput.permissionDecision:
"ask"` with `permissionDecisionReason`, twice: the first was approved and the file appeared,
the second refused and nothing was written, with the refusal arriving as the tool result.
Worth recording how this was nearly misread: the approved run looks from the model's side
exactly like a call that was never questioned, so "the file was created" is not evidence
that nobody was asked. The hook now logs the mode it saw next to the decision, which is
what settled it. Codex support for this decision is not measured yet, so `hook_ask` refuses
with the same text anywhere but Claude Code: a harness that ignores the JSON reads exit 0
as permission to proceed, and a guard that guessed wrong would be a guard that quietly
allows.

**What the owner types into the rejection dialog reaches a hook through the transcript,
in a wrapper only the harness writes.** Measured on this machine's transcripts: the text
lands as a `tool_result` inside a `user` entry, as "The user provided the following
reason for the rejection: <text>", with the entry carrying a UTC timestamp. That wrapper
is what makes the field a trusted channel — an agent cannot put a user entry into the
live transcript — and it is what the write grants are minted from
(`lib/grants.sh`, `hooks/guard-write-scope.sh`). In Codex the mechanism stays silent and
the ask is per file, but the reason is narrower than "no transcript path": the key is
declared and required in Codex's own payload schemas, typed as a nullable string, and
the observed payload had nothing in it. What is absent there is the rejection wrapper,
which is Claude Code's own way of recording an answer to a permission prompt.

**Codex carries the JSON Schema of every hook payload inside its binary, input and
output.** They are embedded as strings titled `pre-tool-use.command.input`,
`user-prompt-submit.command.output` and so on for all ten events, and `strings` on the
binary yields them in full. This is the cheapest measurement available for anything
about Codex hooks: no session, no probe, no guessing at a field name. It is how three
questions were settled at once — `prompt` is the field carrying the owner's message on
`UserPromptSubmit` and it is required; `transcript_path` is declared for Codex too, as
nullable; and `permissionDecision` on `pre-tool-use.command.output` accepts `allow`,
`deny` and `ask`.

**The schema is not the contract, and the last of those three is where it shows.** The
enum allows `ask`; the runtime answers `PreToolUse hook returned unsupported
permissionDecision:ask` and marks the hook **failed**. Measured live on 0.147.0, the same
version whose binary declares the enum. So the embedded schemas are good for field names
and useless for which values are honoured.

**What Codex does with a hook it considers failed matters more than the ask.** It
discards the verdict and falls back to its own policy: in the same run, the refused write
went on to Codex's own "Would you like to make the following edits?" prompt. An error in
a hook there is therefore not a safe refusal, it is no check at all. This is the opposite
of Claude Code, where a hook that cannot answer is treated as blocking, and it is why
`hook_ask` degrading to a refusal outside Claude Code is load-bearing rather than a
workaround: exit 2 is the only shape in which our decision survives.

**So the owner's yes takes a different channel in each tool.** In Claude Code it is the
phrase in the rejection dialog, read out of the transcript. In Codex it is the next chat
message, read from `prompt` on `UserPromptSubmit` by `hooks/prompt-nudge.sh`, which mints
the grant against the scope `guard-write-scope.sh` recorded when it refused. Both rest on
the same property: the harness writes the owner's words, and an agent cannot forge them.
Both are narrow in the same way — the message must be nothing but the phrase, the refusal
must be less than ten minutes old, and the grant covers writing files and nothing else.

One limit is worth knowing before relying on it. Under a live grant the retry gets a
silent allow in Codex rather than an explicit one, so Codex may still put its own
question. Whether it honours an explicit `allow` is unmeasured, and after `ask` the
schema is no longer evidence either way; a decision it rejects would mark the hook failed
and thereby drop our verdict, which is worse than one extra prompt.

**An explicit `permissionDecision: "allow"` suppresses the harness's own permission
prompt; a silent exit 0 does not.** Measured live: a `Write` outside every work tree
under a live grant went through with no dialog of any kind, in a session where the same
write without the grant had just produced the question. This is the difference that lets
a grant actually remove the clicking, and it is why the grant path answers with the JSON
decision (`hook_allow_decision` in `lib/payload.sh`) rather than with silence. Outside
Claude Code it degrades to the ordinary silent allow, because the decision JSON is
unmeasured there.

**The workspace roots a session was opened with are not visible to a hook.** Measured in a
live session with two folders added: the payload carries `cwd`, `effort.level`,
`hook_event_name`, `permission_mode`, `prompt_id`, `session_id`, `tool_input.*`,
`tool_name`, `tool_use_id` and `transcript_path`, and nothing else. The transcript that
`transcript_path` points at does not carry them either, and neither does the project entry
in `~/.claude.json`. The list is rendered into the model's system prompt and stops there,
so a hook that wants to treat every added root as in-scope has nothing to read.

**Codex hooks for one event merge across all four locations and run in parallel.** All
four registrations fired; the order of completion did not match `displayOrder`, so
execution order is not a contract. Registering a new hook does not remove an existing
one, and a layer that uses both `hooks.json` and `config.toml` gets a warning.

**`project_doc_max_bytes` is a combined budget for the project chain, not a per-file
limit.** Two `AGENTS.md` files of 21462 bytes each produced 32770 bytes in the prompt,
the second cut mid-line. The global file in `$CODEX_HOME` is counted separately: a
21.4 KB global plus a 15.1 KB repository file arrive intact.

**`SessionStart` output reaches the model as a separate `developer` message,** with no
wrapper of its own, so any heading has to be written by the hook. A user-level hook runs
even in an untrusted repository; a project-level one does not.

**Claude Code does not reload the rules file mid-session.** Only adding a working
directory root reloads it. An agent rewriting the rules therefore keeps working from the
copy loaded at session start, which is why the check that no rule was lost has to be
done by a fresh session.

## An ambient condition is not a trigger

A skill fires on something the model can see: a word the owner said, or a line some
component put in front of it. A description that says "use this when the session opens
in a repository where X has not been done yet" never fires, however precisely X is
worded, because nothing announces X. The model would have to go looking for a state it
has no reason to suspect.

Found the hard way. A neighbouring repository's skill was written to fire on the first
session in any repository where its choice had not been made, and it fired in none of
them. Its hook was registered correctly in both tools and ran on every session start,
but it reported a machine-level fact — which servers had appeared since last time — and
never the repository-level one, which was the state that needed a decision. Two agents
opened the same unconfigured repository and neither called the skill. Nothing was
broken; the trigger simply did not exist.

Surfacing it is necessary and, on its own, not sufficient. The first fix put the state
into the `SessionStart` output, which is where it belongs logically and where it does not
work. Measured on two restarted sessions: the hook ran, the line reached the transcript,
and both agents answered a greeting without mentioning it. Asked point blank what the
`SessionStart` hook had told it, an agent's first answer was "nothing" — then it corrected
itself, having found the line. Output from that event lands above the owner's first
message, which is the same weak position as the always-loaded rules text, and it reads as
background.

The same state delivered on `UserPromptSubmit`, phrased as an instruction rather than as a
fact, was acted on in the first reply: the agent offered the fix before answering the
greeting. Two things changed at once there, the event and the wording, and both matter.
The position is the structural half: output from `UserPromptSubmit` arrives beside the
prompt, at the end of the context, the opposite end from the rules header.

So the arrangement is two-part. A hook that can see the state writes one instruction-shaped
line into a queue, `~/.cache/agent-rules/nudge/<session id>`, and `prompt-nudge.sh`
delivers the queue beside the owner's next message and clears it. Once per session: a line
repeated on every prompt stops being read after the second time.

The queue is deliberately a plain append-only file rather than a private detail, which
makes it an integration point. Any tool's hook can add a line to it, and the neighbouring
MCP stack does exactly that, falling back to printing when delivery is unavailable. The
readiness marker is per agent: `.delivery-claude-enabled` says nothing about Codex, and
`.delivery-codex-enabled` says nothing about Claude. This matters because the agents share
the queue directory but run different `UserPromptSubmit` registrations. For Codex,
registration alone is not readiness: `install.sh` also checks `enabled` and `trustStatus`
through `hooks/list`. It leaves the Codex marker absent until the owner trusts the hook in
the Codex hook settings and runs the installer again. That check is a Python script, so it
needs `python3`; without it the installer says exactly that instead of blaming trust, and
`scripts/doctor.sh` reports the markers without running the check at all, because a report
that changes nothing should not be starting a Codex process. Inside VS Code those controls are
in Codex Settings; interfaces that expose `/hooks` use it to open the same controls.

`SessionStart` keeps what it is good at: reference material the agent consults rather than
acts on — the repository category, what is open in `tmp/TODO.md`, the active tasks, and
the local rules file for the tool that cannot read it. Things to do go to the queue.

Three states here have that shape: `rules-install` when the classifier profile is missing
or incomplete, `new-repo` when a repository that may have rules has none, and a tray whose
items have been open too long.

**A mechanism can also fail on a format nobody writes in.** The line above about "what is
open in `tmp/TODO.md`" was, for months, produced by counting `- [ ]` checkboxes and
falling back to listing headings when it found none. Counted across five repositories on
this machine: zero checkboxes, in every one of them. Items were written as prose sections,
one of them a hundred and seventy-eight lines long across four items, so only the fallback
branch ever ran and the count it was built around never appeared once. This is the same
failure as an ambient condition, one level down: the trigger existed, the state it read
did not. The fix was to state the tray's format — one line, a date after the checkbox —
and to read the checkbox character rather than the section heading, since headings are
written in whatever language the chat is in. The format deliberately asks for nothing
beyond that line at the moment of capture: the tray exists so that catching a thought
costs nothing, and a rule that makes something get created right then would bring the
prose back.

**A format nobody writes in can also hide inside the test.** Codex's `apply_patch`
arrives in `PreToolUse` with the whole patch in `tool_input.command` and no path field
at all, and one patch can add, rewrite, move and delete several files at once. Measured
on 0.147.0 by Codex, reproduced here with a probe payload. `guard-write-scope.sh` read
`tool_input.file_path`, found nothing, and allowed the call: a probe wrote a file
outside every work tree, silently, leaving nothing in the hook log, because a hook that
exits 0 early logs nothing. The boundary that the whole file is about did not exist for
the editor of one of the two tools it governs.

The selftest had a case named `apply_patch inside the work tree is allowed`, and it
passed on every run. Its fixture put the path in `file_path` — the Claude shape under
the Codex tool name — so the case proved the tool name was accepted and nothing else. A
green test over a payload that the tool never sends is the same failure as a rule over a
state that never arrives, and it is harder to see, because the test's name says the
opposite.

Two things follow, and both are in the code now. Paths come from `hook_paths` in
`lib/payload.sh`, which reads the patch headers at the start of a line — body lines
carry a `+`, `-` or space in the first column, so a diff line that looks like a header
is content. And an editing call whose paths cannot be worked out is stopped rather than
allowed: reading one field and waving the call through when it came back empty is
exactly how this went unnoticed.

**`PreCompact` gives no turn in which to write a file.** It fires before the summary and
its `additionalContext` reaches the model, so it can shape what the summary carries; what
it cannot do is get anything onto disk, because the agent does not act between the hook and
the compaction. So "save the state before compaction" was a rule that fired exactly when it
could no longer be obeyed, and the loss it existed to prevent happened at that moment. The
hook is now written as a last note rather than a safety net, and the state it used to guard
is protected earlier instead: `hooks/note-bookkeeping.sh` counts editing-tool calls since
the active task's `journal.md` was last written and queues a nudge when that crosses a
threshold. Editing calls are the only measure. The transcript's growth in bytes was tried
as a second one and removed after the first live session, where both thresholds fired on
the byte count — at six edits and at twenty — because 150 KB of transcript goes by in a
few calls, so the supplement was deciding everything while the measure meant to be primary
never came close to its number. Raising it would not have been enough: there is no
transcript in a Codex payload, so a byte threshold that fires first in Claude Code means
the two tools nag about different things and each needs calibrating on its own. One
measure has one number to get right.

## Where the names lie

Six cases found while building this. Each one looked settled from its name or its
documentation.

1. **`.claude/rules/*.md` is always loaded, and `globs` in its frontmatter does
   nothing.** A file with `globs: "*.rs"` and `alwaysApply: false` was loaded in full in
   a directory containing no Rust at all. It splits rules into files; it does not make
   them conditional.
2. **`deniedMcpServers` does not remove anything from context.** With
   `deniedMcpServers: ["kibana"]` a session still listed the kibana tools. It is a
   call-time gate, not a context saver. To keep a server's tool names out of a session
   it must not be in scope for that session at all.
3. **`project_doc_fallback_filenames` is not additive.** It substitutes the first
   existing file from the list only where `AGENTS.md` is absent. Next to an existing
   `AGENTS.md` it loads nothing, so it cannot serve as a local overlay.
4. **`model_instructions_file` replaces the built-in base instructions,** not
   `AGENTS.md`, which keeps arriving separately. Using it for local additions risks
   losing the tool's own prompt.
5. **`codex debug prompt-input` is not a full dump of the model request.** It omits the
   top-level `instructions` field and does not execute `SessionStart` hooks.
6. **`project_doc_max_bytes` is documented per file in one place and as a combined size
   in another.** The combined reading is the one the implementation follows.

## Two things worth knowing about cost

Unused MCP servers are cheap and unauthenticated ones are not. With deferred tool
schemas, 165 tool names from seven connected servers cost about 2600 tokens once per
session; the same tools with full schemas would be 80-120 thousand. But nine
unauthenticated cloud connectors produce a 630-character reminder appended to the result
of nearly every tool call, roughly 157 tokens each time, which on a 500-call session is
around 75 thousand tokens: more than every tool name of every server put together.

Reading files is usually the real leak. Across the transcripts measured here,
tool results totalled 13.9 MB, of which `Read` was 11.04 MB over 356 calls, averaging
31 KB per read. All MCP traffic together was 0.6 MB.
