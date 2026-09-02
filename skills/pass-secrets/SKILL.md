---
name: pass-secrets
description: Store credentials in pass so passenv can inject them. Triggers: "положи в pass", "сохрани креды", "сохрани токен", "passenv", setting up secrets for an MCP server or a script that needs environment variables.
---

# Secrets go into pass, in the shape passenv eats

`passenv <namespace> <command>` reads one pass entry, exports its lines as environment
variables and runs the command. Everything below follows from what that script actually
does, not from convention alone: a shape it cannot parse is an error at run time, found
long after the secret was stored.

## The entry

- The entry lives at `mcp/<namespace>`. One namespace per project is the norm.
- The namespace matches `^[a-z0-9][a-z0-9_-]*$`; anything else is refused by passenv
  before it even asks gpg.
- The content is `KEY=VALUE` lines. Keys match `^[A-Za-z_][A-Za-z0-9_]*=`; empty lines
  and lines starting with `#` are skipped; any other line makes passenv stop with
  "Invalid entry".
- Not "password on the first line, fields below" — that classic pass layout is exactly
  what passenv does not eat.

Write it with the multiline mode, so the whole entry is the file:

```
pass insert -m mcp/<namespace>
```

## Multiline secrets

A service-account JSON key or anything else with newlines does not fit a `KEY=VALUE`
line. It goes into its own pass entry, whole, and the `KEY=VALUE` entry next to it gets
a `#` comment saying where to look:

```
# the GCP key is in mcp/<namespace>-gcp-key, fetch it with pass show
API_TOKEN=...
```

## While handling any of this

- Values are never printed: not in answers, not in logs, not in commits. Check an entry
  parses by running the consumer, not by echoing the secret.
- `pass`, like gpg, waits for a PIN or a touch on the token. Silence is not a crash;
  wait for the timeout.
