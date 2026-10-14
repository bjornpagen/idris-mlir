# 0010: the compiler features self-hosting asked for

**Status:** a sketch to flesh out, 2026-10-10; updated 2026-10-14.
The cutover it was written against is built and its arm64 gate is
green (proposals index, "Where the work stands"). Nothing of the six
features is built. Stage 0 of self-hosting compiled the frontend
(c50d176d); the whole frontend has been through pieces of the C++
pipeline in profiling and has never finished it (0003 §2). The
ledger below is those rewrites. This proposal is not on the self-host
path: §"Where it sits" says what the plan needs from it. Claims are
marked: read, measured, recalled, conjecture, decision.

To compile itself, the fork of Idris's compiler (`compiler/idris`) and the
frontend were rewritten wherever this compiler refused their code. Each
refusal is a question about the compiler: is this a construct it should
compile? This proposal answers each one, builds the features the answer
is yes to, and uses them where the code gets better for it.

The rules, decided (the user's, 2026-10-10):
- The point is the compiler and its features, not closeness to upstream.
  A rewrite is never reverted to stay near upstream's code; this code will
  keep moving further from upstream as it is made data-oriented. A rewrite
  is replaced only where a new feature makes the other form more precise
  or faster here.
- The compiler takes the middle way (AGENTS.md): every construct it can
  compile to the code a monomorphic program would be, none that is
  megamorphic. A feature is built when the whole program bounds it.
- A rewrite that made the code faster or its representation better is an
  improvement, and stays.

Today's evidence (measured, 9326d1b8): every "implementation chosen at
runtime" site in the fork was bounded (one implementation, closing over
runtime values), and once the compiler compiled that case it accepted the
code unchanged; `op @{choose k}`, which picks the implementation by a
runtime value, stays refused.

## The ledger: every change self-hosting forced

Read from compiler/idris/README.md ("Honest code", "Rewritten so that
this compiler can compile it", "Ours") and the frontend's history
(2fc2621a, 2299f6dc), each checked for what it costs at runtime and in
precision.

### Improvements: keep

| Change | Why it is better |
|---|---|
| `IdrisMLIR.Term`: `Term n` with `Fin n` variables, from a nested datatype (`Term a`, `Under k a`) | A variable is one natural, a machine word, where the nested form made it a chain of `Free` cells as deep as the binders around it; weakening is index arithmetic (`shift`) in one monomorphic traversal (`cata`, `rename`), where the nested form rebuilt the whole term at a new type at every binder. Both are well scoped. |
| `Core.WithData`: one concrete record per combination of metadata | Fixed fields with fixed types, laid out as a record, where upstream's extensible record was a list of key/value pairs holding a `Type` at runtime, read by a search of the list. Upstream's TTC bytes are kept. |
| `Libraries.Text.Parser.Core`: a grammar is the parser, a closure | No interpretation step: upstream's deep embedding was walked by `doParse` at every step; here each combinator is its clause, and defunctionalization turns the closures into direct code. The `assert_total` marks say where upstream's interpreter asserted the same recursion. |
| the context table on a growable `Linear.Array` | Written in place, grown by doubling, where upstream copied an `IOArray` 10000 slots longer at each fill. |
| `shuffleVars`, `updateLocal`, `removeArgVars` match the position | The match the program runs anyway, on the runtime position; the proof was never a runtime value. |
| the delayed-elaboration knot cut; the shunting yard's stack as a value | No cycle through a mutable cell (the acyclic heap). |
| primitives backed by base's | One meaning per primitive, the runtime's. |
| the bugs fixed | the termination closure (`upstream/21`), `clean`, the lost write after the context table grew, Levenshtein's crash on an empty string. |

### Neutral: keep

Same cost and no loss that matters; nothing to gain by changing them.
- `Idris.CommandLine.OptArg` (no option takes more than one argument, so
  `ActType`'s list of arguments was never more than one).
- `StartExpr` over `Name` (the parser only builds that).
- `decorationFromBounded` without a name (only the stubbed IDE metadata
  read it).
- `OperatorBindingMismatch` holding rendered documents (made only on an
  error).
- `OperatorLHSInfo` a family over `Type`.
- the per-type maps of `TTImp.TTImp.Functor`, `goPairedPTerms` over a pair
  function, parser rules over `WithBounds ()`, `localHelper`'s one result,
  `HasNames` at `NameMap Bool`, `convertMatches` at `Scope`: monomorphic
  code doing what the generic code did.
- the honest rewrites with no runtime cost (`strUncons` for the `strM`
  view; no `believe_me`, `%unsafe` or `%foreign`).

### Regressions: replace when the feature lands

| Change | What was lost | Replaced by |
|---|---|---|
| names, constants and scopes compared as values; `nameEq`, `scopeEq`, `constantEq`, `DecEq Namespace` gone, and where a proof retyped a term the term is rebuilt at the type it needs (`compat`, `compatCaseTree`, `renamedVarAt`) | the proofs, and a traversal that rebuilds a term where a proof retyped it for nothing | 6, then the retyping proofs instead of the rebuilds |
| a TTC's local variable decides its `IsVar` proof from the scope (`isVarAt`) | a walk of the scope for each variable read | 6, if the proof can come from the comparison already made; else measured on the TTC load |
| a scope coercion is a traversal (`embedTerm`, `compatTerm`, `map embed`); `Cast (Doc Void) (Doc ann)` rebuilds the document | a rebuild of every node | the `idr-identity` pass, in the round's function pipeline since the cutover: measured to fire on each |
| `Libraries.Text.Token`: `match` gives text, each user converts | the token's value typed by its kind | 3, if it is free; two small parsers use it |
| `Libraries.Text.Lexer.Tokenizer.Compose`: the tag a `String` | a typed tag; string comparisons | 4, if the tag type is then free |
| Levenshtein over lists of rows | an array | `mlir-linear`'s `Array`, if the bench shows the cost |

## What the cutover settled

The cutover took the handoff's diet, and part of it is what
these features would have built. *Read* (the built frontend: nothing
below is emitted any more):

- **No quantity zero reaches the dialect.** An erased parameter, field,
  argument, capture or binder is not emitted, and the erased grade is gone
  from the dialect. Where an erased value sits in a runtime position the
  frontend cannot drop, it refuses with `unsupported (type)`, naming the
  term and its head. Features 3 and 5 are what would compile some of
  those refusals; until then the refusal is the precise message the bar
  asks for.
- **No newtype.** A data type with one constructor and one runtime field
  is its field. The ledger's "a scope coercion is a traversal" rows lose
  their constructor cost here, before `idr-identity` sees them.
- **Saturated methods and arity.** A method whose implementation the
  instance fixes is one direct, saturated `idr.call`, and a definition is
  emitted at its syntactic arity. That is the bounded case of the
  evidence above, now emitted as direct code rather than recovered by
  specialization.
- **A forced constructor's erased variable is the runtime field it equals**
  (6aa2b517). That is the representational half of
  feature 1; the match on the index replacing the match on the proof is
  still to build (*recalled*: to check against the fixture set).
- **Readable names.** A symbol is its instance key printed; a feature's
  clones and sums read in a dump as the types they are for.

## Where it sits in the self-host plan

Self-hosting is the first priority (0001, stage S): integrate the
cutover, get it green on the owner's machine, break the wall by
measurement (0005's S2 pulled forward for parallel LLVM codegen), then
the handoff's size and the pipeline's memory, then `make self` with
outputs identical under one thread and the pool, then the test runner
off Chez. None of that needs a feature here: the fork already compiles
as rewritten. This proposal starts when `make self` is green, in the
order below, each feature landing only if the native self-compile is no
slower for it; feature 6 waits on 0006's interned names (A0).

## The bar: no runtime price, decided at compile time

Decision: every feature here is compiled away. None of them may introduce
a uniform (boxed) representation, a runtime type code dispatched on at
each use, a dictionary passed at runtime, or an indirect call that the
monomorphic code does not have. Code that uses a feature must run at
least as fast as the code it replaces, on the bench and on the
self-compile, and use no more memory; a replacement that is slower is not
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
(`foreign/idr/`), which already specialize and defunctionalize; the
static part of the program will be normalized in the frontend (0006).

1. **An erased match forced by a runtime value.** A match on an erased
   proof (`First`, `Later`) that a runtime index determines is compiled as
   the match on that index, the detagging Idris's own backends do: the
   proof's constructors map to the index's, decided per data type from its
   constructors' indices. No runtime cost: it is the match the fork now
   writes by hand.
2. **Polymorphic recursion, bounded.** A group of definitions that calls
   itself at other types or implementations (a `Functor` method calling
   `map` through the implementation at a type it binds; a nested datatype
   such as a finger tree) has, in the whole program, the instance set the
   specialization pass's worklist reaches as a fixpoint at compile time.
   When it is finite, each instance is monomorphic and every call direct;
   when it grows (a type built deeper at each call), the program is
   refused naming the type that grows. Not a reason to bring back the
   frontend's nested `Term a`: its `Fin n` form is the better
   representation (the ledger).
3. **A result or field type computed from a runtime value**
   (`tokValue : (kind : k) -> String -> TokType kind`, `ActType`).
   - Where the value is known at the call (a literal kind, a constructor
     in the argument's shape), the instance is specialized on it, as
     `neededShape` already specializes on a parameter's shape: the result
     type reduces and the call is monomorphic. Static normalization
     (0006) will find more of the value in the frontend, where the instance is
     decided, and the `idr` specialization pass extends this across
     calls.
   - Where it is not, the type is the closed sum of the type's whole-
     program image: `TokType` over the kinds the program can construct is
     a finite set of types, so the result is a sum with one variant per
     image type, tagged by the value it was computed from (which the
     program already holds: the tag costs nothing new). A match on the
     value at the use refines the type in each branch to one variant,
     which the dialect's canonicalization turns into the variant's
     payload with no test. A field type computed from another field is
     the same sum inside the data's layout (proposal 0008's flattened
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
   and only if some program needs it: `WithData` stays concrete records,
   which are better (the ledger).

6. **Equality a primitive decides, with its proof.** Base decides
   `DecEq String` and `DecEq Integer` with the primitive and forges the
   proof (`believe_me Refl`), which is why the fork's equality proofs went.
   The proof is erased: a `believe_me` whose result is used only at
   quantity 0 computes nothing, so in base (trusted) it is accepted and
   compiled to the primitive's test alone, with the `Refl` gone. The
   fork's `nameEq`, `scopeEq` and the rest then come back as upstream wrote
   them, at the cost of the comparison they already make. The traversal
   that comparison costs is replaced by interned names (0006 A0). The
   proofs are this feature.

## Staged plan

Each stage is one feature, in the order above:
- its tests: programs with expected output, reject tests for the
  unbounded cases with their precise messages, and an `idr` FileCheck
  test that the construct leaves no sum, tag test or indirect call where
  the value is known;
- the regressions in the ledger it replaces, replaced in the same change;
- the 702-program corpus unchanged but where the feature changes meaning
  by design; the stage-0 self-compile still clean;
- the bench and the self-compile, before and after: no slower, no more
  memory, or the replacement is not taken and the stage says why.

## Measures

- Runtime: the bench and the native self-compile, the code that uses a
  feature against the code it replaces; the bar is "no slower".
- Compile time: the extra instances and sum variants each feature makes,
  and the self-compile's time and peak memory (today 87 s, 1.8 GB on
  stage 0, measured).

## Open questions

- The bound on a sum's variants (3, 4, 5) past which the program is
  refused rather than compiled to a large switch: a measurement rule to
  write here, from the bench.
- How 3's sum meets proposal 0008's flattened layouts and the grades
  (`!idr.lin`, the ownership grades): a variant must keep its payload's
  grade. A quantity-0 payload is not a field at all since the cutover.
- Whether `TokenKind` comes back: it needs 3, and its only users are two
  small parsers.
