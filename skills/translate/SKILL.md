---
name: translate
description: Translate a document or check a copy against its original. Triggers: "переведи", "сверь перевод", "обнови русскую копию", a repository with parallel language copies, a consistency pass over them.
---

# Translating a document

A translation is written as a text in its own language, not word by word. The
original's syntax does not carry across: a construction that works in one language
becomes, in another, a fragment that attaches to nothing.

The test is to read the sentence aloud away from the original. If it does not read,
rewrite it whole instead of patching a word.

## Two passes, in this order

1. **Proofread the translation as a document of its own, without the original in
   view.** Only prose that stands on its own is a translation; prose that makes sense
   solely next to its source is a gloss.
2. **Then check it against the original for meaning.** Not for word order, for meaning:
   what the original asserts, the translation must assert.

The order matters. A comparison done first hides the sentences that do not read,
because next to the original they seem to make sense.

## What survives a word-by-word comparison and is still wrong

- False friends: a word that looks like its counterpart and means something else
  (`underused` rendered as "underrated").
- A dropped `else`, `not`, `only`, `unless`. Negation and scope words disappear without
  leaving a hole in the sentence.
- A number or a unit carried over from an older version of the original.
- An imperative turned into a description: "do X" becoming "X is done".

## Terminology

One term keeps one translation across the whole repository. The same word rendered
differently in neighbouring documents reads as two different things.

Do not invent words the language does not have: a calque looks like a typo rather than a
term. Where no short equivalent exists, describe it.

Names that must not be translated: file names, command names, flags, identifiers, and
error messages quoted verbatim. List them in the plan step rather than deciding case by
case while translating.

## Which file is canonical

The repository says which language is canonical and which files are copies. Edit the
canonical file and bring the copies to it, never the other way around. When a copy has
drifted, the drift is fixed in the copy; if the canonical file turns out to be wrong,
that is a separate change.
