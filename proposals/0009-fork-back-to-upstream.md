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

The rule, decided (the user's, 2026-10-10): this compiler does not take
on all of Idris. It takes the middle way: every construct it can compile
to the code a monomorphic program would be, and none that is megamorphic
(AGENTS.md). So a fork rewrite reverts to upstream's form when the
feature upstream's code uses is one the whole program bounds (each
feature below), and stays when upstream's code needs a megamorphic one,
or is dishonest or wrong (a `believe_me`, an `%unsafe`, a bug). Today's
own evidence (measured, 9326d1b8): every "implementation chosen at
runtime" site in the fork was bounded (one implementation, closing over
runtime values), and the compiler accepted upstream's code unchanged once
it compiled that case; `op @{choose k}`, which picks the implementation by
a runtime value, stays refused.

## The ledger: every change self-hosting forced

Read from compiler/idris/README.md ("Honest code", "Rewritten so that
this compiler can compile it", "Ours") and the frontend's own history
(2fc2621a, 2299f6dc). Each change is a regression to revert (by the
feature named, below), or kept, with the reason. This proposal is done
when every "revert" row is reverted or moved to "keep" with a measurement
that says why.

### Regressions in type precision or code size: revert

| Change | Upstream's form | Revert by |
|---|---|---|
| `Core.WithData`: 13 concrete records | one extensible record, field types computed from a type-level list, a `KeyVal` holding a `Type` | 3, then 5 if 3 does not cover it |
| `IdrisMLIR.Term`: `Term n` with `Fin n` variables | a nested datatype (`Term a`, `Under k a`) | 2 |
| `IdrisMLIR.Term`'s derives and hints written by hand | derived | to check: which rule of the user profile refused them |
| `Libraries.Text.Token`: no `TokenKind`; `match` gives text | `tokValue : (kind : k) -> String -> TokType kind` | 3 |
| `Libraries.Text.Parser.Core`: grammars as closures; `assert_total` on the recursions of `some`, `many` and the rest; combinators no longer `%inline`, `>>` no longer `%tcinline` | a deep embedding read by `doParse`, `SeqEat` hiding its intermediate type, recursion guarded by a constructor | 4 |
| `Libraries.Text.Lexer.Tokenizer.Compose`: the tag a `String` | a tagger to a hidden tag type | 4 |
| `OperatorBindingMismatch`: rendered documents | a value of a hidden type with its printer | 4 |
| `StartExpr` over `Name` | over any name type, hidden | 4, if free; the parser only builds `Name` |
| `decorationFromBounded` keeps no name | a match on the type `a` (`{a = Name}`) | 5; it only fed the IDE metadata (stubbed), so revert for the re-sync, not for a feature |
| recursion at the types it is given: `TTImp.TTImp.Functor`'s maps split per type, `goPairedPTerms` over a pair function, parser rules over `WithBounds ()`, `localHelper`'s one result, `HasNames` at `NameMap Bool`, `convertMatches` at `Scope` | methods calling `map` through the implementation at types they bind; one function over any `t` | 2 |
| `OperatorLHSInfo` a family over `Type` | over a value of an implicit type (`tm -> Type`) | 3 (a parameter that is a value) |
| `shuffleVars`, `updateLocal`, `removeArgVars` match the position | a match on the erased proof the position forces | 1 |
| names, constants and scopes compared as values; `nameEq`, `namesEq`, `scopeEq`, `constantEq`, `DecEq Namespace` and `Libraries.Decidable.Equality` gone | equality decided with proofs (`Maybe (x = y)`, `Dec`) | 6 |

### Honest rewrites with a runtime cost: keep, made free

| Change | Cost | Made free by |
|---|---|---|
| a scope coercion is a traversal (`embedTerm`, `compatTerm`, `map embed`) | rebuilds every node | the `idr-identity` pass (written, unbuilt): a traversal that rebuilds its argument from the same fields is the identity once indices are erased; measure that it fires on each |
| `Cast (Doc Void) (Doc ann)` rebuilds the document | one traversal | the same pass |
| a TTC's local variable decides its `IsVar` proof from the scope (`isVarAt`) | a walk of the scope per variable read | 6 if the proof can be the primitive's; else measure on the TTC load |
| Levenshtein over lists of rows | list cells where upstream had an `IOMatrix` | `mlir-linear`'s growable `Array`, if the bench shows the cost |

### Kept, no regression

- Every `believe_me`, `%unsafe` and `%foreign` gone (the compiler's rules);
  the `strM` view replaced by `strUncons`; the shunting yard's stack
  threaded as a value; the delayed-elaboration knot cut (the acyclic
  heap); primitives backed by base's (one meaning per primitive); the
  context table on a growable `Linear.Array` (an improvement).
- Bugs fixed: the termination check's closure (`upstream/21`), `clean`,
  the lost write after the context table grew, Levenshtein's crash on an
  empty string.
- `Idris.CommandLine.OptArg`: simpler than `ActType` and loses nothing (no
  option takes more than one argument). Decision: keep.
- What was deleted as out of scope (the REPL, IDE mode, code generators,
  the CExp pipeline, source hashes, package scripts) and stubbed
  (`Core.Metadata`): scope, not regressions.

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

6. **Equality a primitive decides, with its proof.** Base decides
   `DecEq String` and `DecEq Integer` with the primitive and forges the
   proof (`believe_me Refl`), which is why the fork's equality proofs went.
   The proof is erased: a `believe_me` whose result is used only at
   quantity 0 computes nothing, so in base (trusted) it is accepted and
   compiled to the primitive's test alone, with the `Refl` gone. The
   fork's `nameEq`, `scopeEq` and the rest then come back as upstream wrote
   them, at the cost of the comparison they already make.

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
