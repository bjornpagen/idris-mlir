# 0009: the fork back to upstream's forms

**Status:** a sketch to flesh out, 2026-10-10, against `main` at 9326d1b8.
Nothing here is built. Claims are marked: read, measured, recalled,
conjecture, decision.

To compile itself, the fork of Idris's compiler (`compiler/idris`) was
rewritten wherever this compiler refused upstream's code. Some rewrites
are better code that upstream would merge. Others exist only because the
compiler cannot yet represent what upstream wrote: dependent types
computed from runtime values, existentials, nested datatypes, types held
at runtime. Those leave the fork weaker than upstream (less precise types,
more code) and cost a merge conflict on every re-sync. This proposal
grows the compiler until each of those rewrites can be reverted to
upstream's form, and then reverts it.

The rule, decided: a fork rewrite stays only where upstream's code is
dishonest or wrong (a `believe_me`, an `%unsafe`, a bug). Where upstream's
code is ordinary Idris that the compiler refuses, the compiler is what
changes (AGENTS.md: the compiler implements Idris 2 fully over prelude and
base). Today's own evidence (measured, 9326d1b8): every "implementation
chosen at runtime" site in the fork was a gap in the compiler, and closing
it accepted upstream's code unchanged.

## The rewrites to revert, each with the feature it needs

Read from compiler/idris/README.md, "Rewritten so that this compiler can
compile it".

| Rewrite | Upstream's form | What the compiler lacks |
|---|---|---|
| `Core.WithData`: 13 concrete records | one extensible record, `WithData fields a`, whose field types are computed from a type-level list and whose `KeyVal` holds a `Type` | field types computed from an index; a `Type` held at runtime |
| `IdrisMLIR.Term` / `Term n` with `Fin n` | a nested datatype (`Term a`, `Under k a`) | polymorphic recursion over a nested datatype |
| `Libraries.Text.Token`: no `TokenKind`, `match` gives text | `tokValue : (kind : k) -> String -> TokType kind` | a function type whose result is computed from a runtime argument |
| `Libraries.Text.Parser.Core`: grammars as closures | a deep embedding, `SeqEat` hiding its intermediate type | existentials (a constructor that hides a type argument) |
| `Libraries.Text.Lexer.Tokenizer.Compose`: tag as a `String` | a tagger to a hidden tag type | existentials |
| `Error`'s existential as rendered docs | a hidden type in an error | existentials |
| `Idris.CommandLine.OptArg` | `ActType : List OptType -> Type`, the action's type computed from the arguments | a field type computed from another field |
| `StartExpr` over `Name` | over any name type, hidden | existentials |
| `decorationFromBounded` with no name | a match on the type `a` (`{a = Name}`) | a `Type` at runtime, matched on |
| the `Functor`/traversal maps split per type | methods calling `map` through the implementation at types they bind | polymorphic recursion through implementations |
| `shuffleVars`, `updateLocal`, `removeArgVars` match the position | a match on the erased proof (`First`, `Later`) that the runtime position forces | a match on an erased value that a runtime value determines |

Some of these may be better left as they are (decision deferred to each
stage, by the rule above): `OptArg` is simpler than `ActType` and loses
nothing, since no option takes more than one argument; the match on the
position is arguably the honest form.

## The features, roughly in order of cost (conjecture)

1. **An erased match forced by a runtime value.** When an index the
   program holds at runtime determines which constructor an erased proof
   has, the match compiles to a match on that index. Small: it is the
   detagging Idris's own backends do.
2. **Polymorphic recursion with a finite instance set.** The closure of
   instances is computed as a fixpoint within the budgets; a nested
   datatype whose recursion only deepens an erased index has one
   representation. Reverts `Term`, the traversals.
3. **A function type whose result depends on its argument, and a field
   type that depends on another field.** Either an instance per shape of
   the argument (as `neededShape` already does for parameters), or one
   uniform representation, a box, for a value whose type is only known at
   runtime. Measurement decides which is the default.
4. **Existentials.** A constructor that hides a type holds its value
   boxed, with whatever its uses need (its implementations) beside it,
   closure-converted as defunctionalization already converts captures.
5. **Types at runtime.** A `Type` held or matched at runtime is a value of
   a closed runtime type of type codes. Last, and only if a revert needs
   it: the others may cover `WithData`.

## Staged plan

Each stage is one feature: its tests (accepted programs with expected
output, and the rejections it replaces), the fork rewrites it lets
revert, reverted in the same change, the 702-program corpus unchanged but
where the feature changes meaning by design, and the stage-0 self-compile
still clean.

## Measures

- Fork diff against upstream at the pin, in lines, before and after each
  stage (measured each time; it should only fall).
- Self-compile time and peak memory (today 87 s, 1.8 GB, measured).
- Runtime cost of each uniform representation chosen in 3 and 4, against
  an instance per shape, on the bench.

## Open questions

- Which of 3's two representations is the default, and the threshold that
  picks the other (a measurement rule to write here).
- Whether `TokenKind` is reverted: it needs 3, and its only users are two
  small parsers.
