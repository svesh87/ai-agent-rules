*English · [Русский](TODO.ru.md)*

# TODO

The intake tray. Catching a thought costs one line and touches nothing else: a date
right after the checkbox and the thought itself. Nothing is created elsewhere while
capturing, because capture is the one operation here that has to stay free.

An item that has grown a body moves to `tmp/ideas/<date>-<slug>.md` when it is next
picked up, with the line here pointing at it. That happens at the moment somebody works
the item, never at the moment it is thrown in.

The state is the character in the checkbox, not the section: `- [ ]` open, `- [x]`
closed, `- [>]` waiting on the owner. The hooks read the character, because headings
get written in whatever language the chat is in. The sections below are for the person
reading the file.

The date is not decoration. `tmp/` is not in git, so there is no other way to tell how
long something has been sitting here, and the session banner uses it to say when the
tray needs going through.

An item that has been dealt with stops being open in the same edit: `- [x]` with the
task it became, or `- [x]` with the reason it was rejected. Nothing is closed silently.

## Open

- [ ] <YYYY-MM-DD> <one line>
- [ ] <YYYY-MM-DD> <one line> -> `ideas/<date>-<slug>.md`

## Waiting on the owner

- [>] <YYYY-MM-DD> <what only the owner can decide or run>

## Closed

- [x] <YYYY-MM-DD> <one line> -> `archive/<YYYY-MM>/<date>-<slug>/`
- [x] <YYYY-MM-DD> <one line> — rejected: <reason>
