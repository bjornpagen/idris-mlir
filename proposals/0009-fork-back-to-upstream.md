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

## The bar: no runtime price, decided at compile time

Decision: every feature here is compiled away. None of them may introduce
a uniform (boxed) representation, a runtime type code dispatched on at
each use, a dictionary passed at runtime, or an indirect call that the
monomorphic rewrite does not have. The reverted upstream code must run at
least as fast as the rewrite it replaces, on the bench and on the
self-compile, and use no more memory; a revert that is slower is not
taken. What makes this possible is the one fact this compiler always has:
the whole program (memory: whole program, always). Every set the features
need (the types an existential is built at, the kinds a dependent result
is computed from, the types held at runtime) is finite and known at
compile time, so each runtime choice becomes either a specialization or a
closed sum whose variants are exactly the program's cases, which MLIR's
passes then specialize, fold and defunctionalize like any other data.
Where a set is not finite (a type that grows without bound at runtime),
the program is refused with a message that names the growing value, never
boxed.

## The features, each as a compile-time construction

Roughly in order of cost (conjecture). Each lands in the Idris side
(classification, instances) and in the `idr` dialect's passes
(`foreign/idr/`), which already specialize, evaluate at compile time and
defunctionalize.

1. **An erased match forced by a runtime value.** A match on an erased
   proof (`First`, `Later`) that a runtime index determines is compiled as
   the match on that index, the detagging Idris's own backends do: the
   proof's constructors map to the index's, decided per data type from its
   constructors' indices. No runtime cost: it is the match the rewrite
   writes by hand.
2. **Polymorphic recursion over nested datatypes.** `Term (Under k a)`
   differs from `Term a` only in an erased index, so it has one
   representation (instances keyed by representation, as the
   runST/phantom rule already keys them). The instance set of a recursion
   through implementations is computed as a fixpoint at compile time, in
   the specialization pass's worklist; it is finite or the program is
   refused naming the type that grows. Every call is direct.
3. **A result or field type computed from a runtime value**
   (`tokValue : (kind : k) -> String -> TokType kind`, `ActType`).
   - Where the value is known at the call (a literal kind, a constructor
     in the argument's shape), the instance is specialized on it, as
     `neededShape` already specializes on a parameter's shape: the result
     type reduces and the call is monomorphic. The `idr` specialization
     pass extends this across calls after compile-time evaluation has
     found more of the value.
   - Where it is not, the type is the closed sum of the type's whole-
     program image: `TokType` over the kinds the program can construct is
     a finite set of types, so the result is a sum with one variant per
     image type, tagged by the value it was computed from (which the
     program already holds: the tag costs nothing new). A match on the
     value at the use refines the type in each branch to one variant,
     which the dialect's canonicalization turns into the variant's
     payload with no test. A field type computed from another field is
     the same sum inside the data's layout (proposal 0006's flattened
     layouts place it), so `ActType`'s action is stored unboxed.
4. **Existentials** (`SeqEat`, a tokenizer's hidden tag, a hidden name
   type). A constructor that hides a type is, in the whole program, built
   at finitely many types: the hidden type becomes a closed sum over those
   construction sites' types, exactly as defunctionalization turns a
   closure's captures into a labelled sum keyed by concrete types. The
   operations used on the hidden value become a match on that label,
   which specialization removes wherever the construction site reaches the
   use (the parser combinators: every grammar is a constant, so most
   collapse to direct code). No box, no vtable.
5. **Types at runtime** (`KeyVal` holding a `Type`, a match on `{a =
   Name}`). A `Type` held at runtime is a value of a closed enum of the
   types the program stores there, generated per site, and a match on it
   is a switch on that enum, folded at compile time wherever the type is
   known (always, for `WithData`, whose field lists are constant). Last,
   and only if a revert needs it; 3 and 4 may cover `WithData`.

## Staged plan

Each stage is one feature, in the order above:
- its tests: programs with expected output, reject tests for the
  unbounded cases with their precise messages, and an `idr` FileCheck
  test that the construct leaves no sum, tag test or indirect call where
  the value is known;
- the fork rewrites it lets revert, reverted in the same change;
- the 702-program corpus unchanged but where the feature changes meaning
  by design; the stage-0 self-compile still clean;
- the bench and the self-compile, before and after: no slower, no more
  memory, or the revert is not taken and the stage says why.

## Measures

- Fork diff against upstream at the pin, in lines, before and after each
  stage (measured each time; it should only fall).
- Runtime: the bench and the native self-compile, the reverted upstream
  code against the rewrite it replaces; the bar is "no slower".
- Compile time: the extra instances and sum variants each feature makes,
  and the self-compile's time and peak memory (today 87 s, 1.8 GB on
  stage 0, measured).

## Open questions

- The bound on a sum's variants (3, 4, 5) past which the program is
  refused rather than compiled to a large switch: a measurement rule to
  write here, from the bench.
- How 3's sum meets proposal 0006's flattened layouts and the grades
  (`!idr.lin`, `!idr.erased`): a variant must keep its payload's grade.
- Whether `TokenKind` is reverted: it needs 3, and its only users are two
  small parsers.
