<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0014: the compiler features self-hosting asked for

**Status (2026-10-19, read at 77eaa5b1):** open. Built: feature 2,
bounded polymorphic recursion, as the growth check (3fc4d2e4,
`Frontend/Growth.idr`, proved in `Proof/Growth.idr`; fixtures
`polymorphic-recursion-swapped`, `polymorphism-*`); the match on
`Delay` (bfdcac70); feature 1's representational half, a forced
constructor's erased variable as the runtime field it equals (6aa2b517,
`Translate/Forced.idr`); and no count refusing a program (c7aa7b62,
bfdcac70). Not built: features 1, 3, 4, 5 and 6, all **AFTER-SELF**.
**First step: feature 1**, starting with its check that forced indices
tell apart the alternatives of every erased match in base, the fork and
the corpus, taken when the queue reaches this proposal after `make
self`; feature 6 may land at any point after `make self`. Claims are
marked *read*, *measured*, *recalled*, *conjecture* or *decision*.

To compile itself, the fork of Idris's compiler (`compiler/idris`) was
rewritten wherever this compiler refused its code. Its README records
each rewrite and why it stays (`compiler/idris/README.md`, "Honest code"
and "Rewritten so that this compiler can compile it"). Each refusal asked
whether the compiler should compile the construct. This file answers yes
for the bounded ones and designs each feature; only megamorphic
constructs stay refused.

## Self-hosting needs none of it

The self-compile's frontend step passes with no refusal
(`bench/records/2026-10-17-self-growth.md`), and nothing `make self`
compiles uses a construct a feature here admits (*read* 2026-10-15). If stage 1 meets a
refusal in the frontend, the fork or `libs/`, that code is rewritten
inside the subset; no feature here is built first to get past it
(*decision*, the owner's regimented subset, 47f97059; the two hosts,
AGENTS.md).

## The refusals the features remove

ODS's `Idr_Rule` is the account of what the compiler refuses: each case
carries its `RuleCategory` (`foreign/idr/include/idr/IR/IdrBase.td`,
generated into `compiler/src/IdrisMLIR/Syntax/Idr.idr`). AGENTS.md states
the rule. The table lists the frontend's refusals of constructs inside the
language that a feature compiles where the whole program bounds them
(*read*; paths are under `compiler/src/IdrisMLIR/Frontend/`; fixtures are
reject tests under `tests/`):

| `unsupported (<rule>)` | Refused today | Site | Fixture | Feature |
|---|---|---|---|---|
| `match` | a match on an erased value, between constructors that a runtime index tells apart | `Translate/Cases.idr`, `forced` | none | 1 |
| `primitive` | a match on a `Double` literal | `Cases.idr`, `litAlternatives` | `primitive-double-match` | 1's stage (D13) |
| `type` | a type computed from a runtime value; `Type` in a runtime position | `Translate/Terms.idr` (`inRuntime`, the `coreType` sites), `Translate/Types.idr`, `Translate/Instances.idr` | `type-dependent` | 3, 5 |
| `dependent field` | a field whose type depends on another field (a `Type` field among them) | `Types.idr` | `dependent-field-type-field` | 3, 5 |
| `string primitive` | a match on a constant with no literal (a primitive type held as a value) | `Cases.idr`, `litAlternatives` | none | 5 |
| `static argument` | a type, shape or implementation not known statically; a partial application missing one | `Instances.classify`, `Terms.idr`, `Cases.idr` (`staticCase`) | none | 5, 4 |
| `dictionary field` | one constructor built with two implementations | `Translate/Dictionaries.idr` | `dictionary-field-two-implementations`, `dictionary-field-opaque-type` | 4 |
| `runtime closure` | a constructor's constraint given an implementation that closes over runtime values | `Instances.classify`, `Terms.idr` | `runtime-closure-scope-constructor-field`, `runtime-closure-shape-constructor-field` | 4 |
| `deprecated` | a call of base's `%deprecate`d `setByte`, `getByte` or `bufferData` | `Registry/Primitives.idr` (`deprecatedForeign`, `deprecatedDef`), `Profile.idr` (`visit`), `Terms.idr` | `deprecated-get-byte` | 6's stage (D14) |

Under these rules, some refusals stay:
- an implementation chosen by a runtime value
  (`runtime-closure-implementation`, `runtime-closure-index-function`);
- a computed type whose image is infinite and whose value is not known
  at the call (feature 3);
- the `static argument` refusal where the compiler would have to run a
  definition Idris does not prove ends to learn a static value (the
  owner's ruling, narrowed on 2026-10-15 to where a normaliser runs
  definitions).

A primitive the runtime does not define (a fixed-width negation, the
`Char`-`Double` and `String`-`Char` casts) is no feature (D15).

ODS gives `match`, `primitive`, `string primitive` and `deprecated` the
category `OutsideLanguage`, and the other five `Megamorphic`. Neither
category describes the bounded sites in the table. So a feature's stage
must leave its rule with only the sites its category describes.

## The bar: no runtime price

*Decision* (D2): every feature is compiled away. No feature may bring in:
- a uniform (boxed) representation;
- a runtime type code dispatched on at each use;
- a dictionary passed at runtime;
- an indirect call the monomorphic code does not have.

Code that uses a feature runs at least as fast as the code it replaces,
on the bench and on the self-compile, and uses no more memory.
Otherwise the replacement is not taken. The whole program is the unit of
meaning, so every set a feature needs is finite and known at compile time:
- the types an existential is built at;
- the values a dependent type is computed from;
- the types held at runtime.

Each runtime choice becomes a specialization, or a closed sum whose
variants are exactly the program's cases. The optimizer then folds and
specializes that sum like any other data. Where a set is not finite, the
program is refused, with a message that names the growing value; it is
never boxed.

## The features, each a compile-time construction

Each is built in the frontend, which holds the whole program's types and
decides every set below (AGENTS.md: Idris does types). What the frontend
emits is ordinary `idr` data and calls. No pass of the pipeline has a case
for a feature (D9). Static normalization (0010's A3) will find more
values known in the frontend. They are listed roughly in order of cost
(*conjecture*).

- **1. An erased match forced by a runtime value.** A runtime index can
   determine which constructor an erased proof has (`First`, `Later`).
   A match on such a proof compiles as the match on that index, as Idris's
   own backends detag. The proof's constructors map to the index's, per
   data type, by the view `Translate/Forced.idr` computes. It is the match
   the fork writes by hand now, so it costs nothing. Where Idris accepted
   the match, forced indices tell its alternatives apart (*conjecture*,
   checked on every erased match in base, the fork and the corpus).
   *Decision:* once that check holds, a match they do not tell apart is
   an internal error (a broken invariant), and `forced`'s refusal is
   deleted. Until then it stays the refusal, which names the runtime value
   to match on. The same stage compiles a match on a `Double` literal
   (D13).
- **3. A result or field type computed from a runtime value**
   (`tokValue : (kind : k) -> String -> TokType kind`, `ActType`).
   - Where the value is known at the call, the instance is specialized on
     it, as `Instances.neededShape` specializes on a parameter's shape.
   - Where it is not, the type is the closed sum of its whole-program
     image, one variant per image type, tagged by the value it was
     computed from. A match on the value refines the type in each branch:
     the frontend emits the sum's match with that arm alone reachable
     (Idris proved the others impossible), and canonicalization turns it
     into the variant's payload, with no test. A field type computed from
     another field is the same sum inside the data's layout (0012 places
     it).
   - **The image** (*decision*) is computed from the type function
     itself. It is never computed by a flow analysis of runtime values,
     which would be a second label analysis beside defunctionalization's.
     Over an index type with finitely many values, the image is the normal
     form at each value. Over any other index type, it is the language of
     the function's clauses read as a grammar, where a recursive call
     stands for the whole image. That language is finite when no recursive
     call sits under a type constructor (a regular tree grammar, whose
     finiteness is decidable, *recalled*). An infinite image with the
     value unknown is megamorphic and refused, naming the function and the
     value.
   - **The sum** (*decision*) is an ordinary data type, an identified type
     whose body holds its constructors (the cutover's D29). An untagged
     union discriminated by another value is rejected: it would be a
     second kind of sum in the dialect. Whether the tag shares storage
     with the value is a layout question, and 0012 decides it by
     measurement.
- **4. Existentials** (`SeqEat`, a tokenizer's hidden tag, a constraint
   field). A constructor that hides a type or holds an implementation is
   built, in the whole program, at finitely many witnesses. The hidden
   value becomes a closed sum over those witnesses, as defunctionalization
   turns captures into a sum. An implementation that closes over runtime
   values carries them in its variant. Specialization and case of known
   constructor remove the match wherever construction reaches use (every
   grammar is a constant).
   - **How** (*decision*). The constructor's dictionary table generalizes
     from one implementation per field to the set of witnesses the
     program builds. That set is a monotone relation filled by the
     instance worklist: each match requests its alternative once per
     witness, keyed by the witness, so a new witness is a new request and
     never a restart. This deletes the rounds that restart translation
     from `main` (`translateFrom` in `Frontend/Finite.idr`). 0011's O3 is
     the same fixpoint, as tables.
- **5. Types at runtime** (`KeyVal` holding a `Type`; a match on
   `{a = Name}`). *Decision:* feature 4's relation for a field or argument
   with no payload. A `Type` held at runtime is a constructor of the
   enumeration of the types the program stores there. A match on it is a
   switch, folded wherever the type is known. A partial application
   missing a type parameter is the same value passed late. It lands right
   after 4. `WithData` stays concrete records, which are better.
- **6. Equality a primitive decides, with its proof.** Base decides `DecEq`
   for primitive types with the primitive, and forges the proofs with
   `believe_me` (`third_party/Idris2/libs/base/Decidable/Equality.idr`,
   `FromEq`). `Profile.idr`'s `visit` refuses every `Builtin BelieveMe`,
   trusted or not; `Translate/Terms.idr` admits only the exit's.
   - **The rule** (*decision*, D8): in a trusted library (base, and the
     fork, `Library Compiler` in `Registry/Libraries.idr`), a
     `believe_me` whose result carries no runtime value is accepted.
     That is the case when its result is used only at quantity 0, or when
     its target's representation has at most one value: `Equal x y` has
     one constructor and no runtime field
     (`third_party/Idris2/libs/prelude/Builtin.idr`), and `Void` has none.
     The rule reads the target's data type, whose body holds its
     constructors. Anywhere else, and in user code always, `believe_me`
     stays an escape hatch. Compiled, `decEq` is the primitive's test
     alone, and the fork's `nameEq`, `scopeEq` and the rest come back as
     upstream wrote them. The cost of comparing strings by traversal is
     0011's O1 over 0010's interned names.
   - **Base's deprecated names** (*decision*, D14), in the same stage,
     since it edits the profile's rules. `setByte`, `getByte` and
     `bufferData` compile as base defines them:
     - `getByte` is `getBits8` widened to `Int`;
     - `bufferData` is `bufferData'` widened;
     - `setByte` stores its `Int` cast to `Bits8`, by the language's
       cast.

     Idris accepts them with a warning (`Core.Core`'s `Deprecated`
     warning). The stage deletes the registry's `Deprecated` hook kind
     (`Registry/Entry.idr`), its two entry builders, the profile's and
     `Terms.idr`'s checks, and the `Deprecated` rule. Its reject fixture
     becomes a program test.

## Rewrites a feature replaces

The fork's other rewrites stay by D1, each recorded in its README. These
regressions are replaced when their feature lands, if the bar holds:

| Rewrite (`compiler/idris/README.md`) | What was lost | Replaced by |
|---|---|---|
| names, constants and scopes compared as values (`nameEq`, `scopeEq`, `constantEq`, `Namespace`'s `DecEq` gone); a term rebuilt where a proof retyped it (`compat`, `compatCaseTree`, `renamedVarAt`) | the proofs, and a rebuild for nothing | 6 |
| `isVarAt` decides a TTC variable's `IsVar` from the scope | a walk of the scope for each variable read | 6 (quantity 0), else measured on the TTC load |
| scope coercions as traversals (`embedTerm`, `compatTerm`, `map embed`, `annotateVoid`) | a rebuild of every node | `idr-identity`, checked with `not-called` in feature 1's stage; a call left over is fixed in `idr-identity` |
| `Libraries.Text.Token`: `match` gives text | the token's value typed by its kind | 3 (D11) |
| `Libraries.Text.Lexer.Tokenizer.Compose`: the tag is a `String` | a typed tag | 4 (D11) |
| Levenshtein over lists of rows | an array | no feature: `libs/mlir-array`'s `LArray`, if the bench shows the cost |

## Staged plan

The stages run in order: 1, 3, 4, then 5, which reuses 4's relation.
Feature 6 may land at any point after `make self`, since it touches only
the profile's rules, the registry's deprecated entries and the fork's
equality code. Each stage brings:
- **Tests.** Programs with expected output. Each reject fixture the
  table assigns to the feature becomes a program test. Reject tests
  cover the unbounded cases, with their
  messages. The compile-time property is stated with idr-expect's
  existing `matches-nothing`, `direct-calls`, `no-closures` and
  `not-called`, never with a new property or an op sequence.
- **The ledger.** The rows above that the feature replaces are replaced
  in the same change.
- **Unchanged suites.** `make test`, `make test-idr` and the emitted
  corpus are unchanged, except where a refusal becomes a program by
  design. `make self` is green: stage 2 is byte-identical to stage 3,
  with the determinism check (`harness/lib/determinism.sh`).
- **The bench and the native self-compile**, old binary against new
  under identical conditions, best of five (the cutover's §10 margins;
  0009 D35). No bench program may be more than 2% slower, the
  self-compile's wall no more than 5% slower, and neither may use more
  memory. Otherwise the replacement is not taken, and the stage says why.

## Measures

Each stage records, as records and never as refusals:
- the extra instances and sum variants the feature makes;
- the largest boxed sum it builds (past 2^16 tags a sum is two-level);
- the native self-compile's wall time and peak resident memory, against
  `make self`'s first record.

No native figure exists yet. Chez's stage-0 run (137 s at 9.1 GB,
c50d176d) measures Chez and is not the bar.

## Decisions

- D1 (the user's, 2026-10-10). The point is the compiler, not closeness
  to upstream. A rewrite is replaced only where a feature makes the other
  form more precise or faster here. A feature is built when the whole
  program bounds its construct. A rewrite that made the code faster or
  its representation better stays.
- D2. The bar: every feature compiled away, with no runtime price.
- D3. Of the constructs inside the language, only megamorphic ones stay
  refused. What is outside the language stays out. No bound is set on a
  sum's variants.
- D4. Feature 2: built, as the growth check (3fc4d2e4).
- D5. Feature 3's image comes from the type function's clauses, and its
  sum is an ordinary data type.
- D6. Feature 4 is a monotone witness relation in the instance worklist;
  the dictionary restart goes.
- D7. Feature 5 is built, as feature 4's relation without a payload.
- D8. Feature 6's rule: a trusted library's `believe_me` whose result
  carries no runtime value. It does not wait for 0010's A0.
- D9. Every feature is built in the frontend; no pass of the pipeline
  has a case for one.
- D10. A variant keeps its payload's quantity in its type (`!idr.lin<T>`
  for quantity 1), and the verifier checks it after every pass. A
  quantity-0 payload is no field. Ownership is decided by `idr-rc` on the
  sum, as on any data.
- D11. `TokenKind` comes back with feature 3, and the `Compose` tag with
  feature 4, each as its stage's proof on real code, if the bar holds.
  Otherwise the rewrite stays (D1).
- D13. A match on a `Double` literal is the runtime's `Double` equality,
  tested against each literal in the alternatives' order. This is the
  meaning the checker's evaluator gives it (`tryAlt`'s `ConstCase` in
  `compiler/idris/src/Core/Normalise/Eval.idr`, over `Eq Constant` in
  `Core/TT/Primitive.idr`). It lands in feature 1's stage.
- D14. Base's three deprecated buffer names compile as base defines them,
  and the `deprecated` rule goes: Idris warns and accepts them.
- D15. A primitive the runtime does not define stays `unsupported
  (primitive)`. Neither the prelude nor base calls one. A program that
  needs one gets it in `runtime/`, with its documented semantics and its
  test.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- D13's form: a literal `Double` match is a chain of `arith.cmpf oeq`, each
  matched as an `i1`; `match_lit` gets no `f64` case. Emit already lowers
  `==` on `Double` to `cmpf oeq` (`Emit/Operations.idr`); a literal
  `Double` match is still refused (`Translate/Cases.idr`).

## The growth check's known limits

Finite programs the polymorphism rule (the growth check, 3fc4d2e4) still
refuses, from its design's last text at 77eaa5b1: a type family whose
value computes on static arguments; beta summing two families' heights
(`tests/polymorphism-growth-mutual`); `StateT s (StateT s' m)`. Each is a
bounded construct this compiler should compile (AGENTS.md: only a
megamorphic construct is refused), so each is a feature here when a
program needs it.
