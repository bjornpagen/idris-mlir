# 0011: the compiler features self-hosting asked for

**Status:** approved with the queue on 2026-10-14 (proposals index).
Written 2026-10-10 as a sketch; fleshed out and decided 2026-10-14
against 0004's pipeline cutover. Nothing of the six features is built.

The tree (*measured*, HANDOFF.md, 0002): the cutover of 0002 is
committed and builds on arm64 macOS, where `make test` was 415/415 at
7a27fd34, before the opt-in SCC pipeline that 0004 deletes. x86_64 Linux
is NotRun. Stage 0 compiled the frontend on Chez (c50d176d: 58,305
functions in 137 s at 9.1 GB peak); stage 1 has never finished, and
0004's cutover is what it waits on (0004 §3.1). The ledger below is the
rewrites self-hosting forced. This proposal is not on the self-host
path: "Where it sits" says what the plan needs from it. Claims are
marked: *read*, *measured*, *recalled*, *conjecture*, *decision*.

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
- The compiler takes the middle way (AGENTS.md): every construct whose
  runtime choices the whole program bounds is compiled to the code a
  monomorphic program would be; a megamorphic one is refused. A feature
  is built when the whole program bounds it.
- A rewrite that made the code faster or its representation better is an
  improvement, and stays.

Today's evidence (*measured*, 9326d1b8): every "implementation chosen at
runtime" site in the fork was bounded (one implementation, closing over
runtime values), and once the compiler compiled that case it accepted the
code unchanged; `op @{choose k}`, which picks the implementation by a
runtime value, stays refused (*read*: `Translate/Instances.idr:255`,
`Translate/Terms.idr:855`; `tests/reject/runtime-closure-implementation`).
Paths under `Translate/` are in `compiler/src/IdrisMLIR/Frontend/`.

## What stays refused

*Decision*, agreeing with 0004 §2.5, which owns the rule for the whole
compiler:

- **Megamorphic constructs,** refused by the frontend with the site and
  the value whose set is unbounded: an implementation chosen by a runtime
  value (`runtime-closure-implementation`, `runtime-closure-index-function`)
  and a recursion that builds its type deeper at each call
  (`polymorphism-growing-shape`, `polymorphism-nested`). Feature 2 makes
  the second exact.
- **What is outside the language,** which no feature here touches
  (AGENTS.md): `%foreign`, threads, collector finalizers, raw pointers,
  signal handlers, processes, and escape hatches, forged worlds and
  pragmas in user code.
- **No other construct.** No budget, no cap on a sum's variants, no
  count of instances and no optimization decides whether a program
  compiles, in the frontend or in the pipeline (0004 §2.5). A finite set
  is a sum, however large: MLton's closure conversion compiles a large
  set to a `case` with one arm per lambda, with no cap, no refusal and no
  boxed fallback (0004 §2.3).

The pipeline's other refusals are about representation limits and the
program's own promises, not constructs, and are not this proposal's
(*read*): a cell past its header's counted slots or tags
(`unsupported (layout)`, `foreign/idr/lib/IR/Layout/Layouts.cpp:95`,
`lib/IR/OpsData.cpp:93-98`; 0009's ground), a knot through a mutable cell
(`unsupported (cycle)`, `lib/IR/Verify/Knots.cpp:100`; the acyclic heap),
and a broken in-place promise (`unsupported (uniqueness)`,
`lib/Transforms/Demand/Demand.cpp:79`; a fact of `mlir-linear`'s types
after 0004 §4.1). None of them is a budget.

Every other refusal the frontend makes today, on a construct inside the
language, is a missing feature (*read*: the rules are
`compiler/src/IdrisMLIR/Rule.idr:12-39`; the sites and fixtures below):

| Refusal today, `unsupported (<rule>)` | Where | Fixture | Removed by |
| --- | --- | --- | --- |
| `match`: a match on an erased value, between constructors a runtime index tells apart | `Translate/Cases.idr:534-539` | none yet; the fork's `shuffleVars`, `updateLocal` and `removeArgVars` were rewritten around it | 1 |
| `laziness`: a match on `Delay` (not asked by self-hosting; taken so the end state holds) | `Cases.idr:498, 736` | none | 1's stage: a force bound to the pattern's variable, as upstream compiles `DelayCase` (`third_party/Idris2/src/Compiler/CompileExpr.idr:322-327`, *read*) |
| `polymorphism`: a recursive component that passes a type or implementation other than its own, unchanged, even when the set it reaches is finite | `Translate/Recursion.idr:139-152` | none for the bounded case | 2 |
| `compile-time budget`: more than 4,096 instances of one definition | `Translate/Instances.idr:32-39, 110-112` | none | 2, whose termination argument deletes it |
| `type`: a type computed from a runtime value, or `Type` in a runtime position | `Translate/Types.idr:435-437`; `Terms.idr:137, 318` | `type-dependent` | 3 (a computed type), 5 (a type held) |
| `dependent field`: a field whose type depends on another field, a `Type` field among them | `Types.idr:509-512` | `dependent-field-type-field` | 3, 5 |
| `dictionary field`: one constructor built with two implementations | `Translate/Dictionaries.idr:87-112, 135-157` | `dictionary-field-two-implementations`, `dictionary-field-opaque-type` | 4 |
| `runtime closure`: a constructor's constraint given an implementation that closes over runtime values | the message of `Instances.idr:255` (9326d1b8) | `runtime-closure-scope-constructor-field`, `runtime-closure-shape-constructor-field` | 4 |
| `static argument`: a type or implementation argument not known statically, or a partial application missing one | `Instances.idr:214-227`; `Terms.idr:668-670` | none | 5 (a type held at runtime), 4 (an implementation held) |

## The ledger: every change self-hosting forced

Read from `compiler/idris/README.md` ("Honest code", "Rewritten so that
this compiler can compile it", "Ours") and the frontend's history
(2fc2621a, 2299f6dc), each checked for what it costs at runtime and in
precision.

### Improvements: keep

| Change | Why it is better |
|---|---|
| `IdrisMLIR.Term`: `Term n` with `Fin n` variables, from a nested datatype (`Term a`, `Under k a`) | A variable is one natural, a machine word, where the nested form made it a chain of `Free` cells as deep as the binders around it; weakening is index arithmetic (`shift`) in one monomorphic traversal (`cata`, `rename`), where the nested form rebuilt the whole term at a new type at every binder. Both are well scoped. |
| `Core.WithData`: one concrete record per combination of metadata | Fixed fields with fixed types, laid out as a record, where upstream's extensible record was a list of key/value pairs holding a `Type` at runtime, read by a search of the list. Upstream's TTC bytes are kept. |
| `Libraries.Text.Parser.Core`: a grammar is the parser, a closure | No interpretation step: upstream's deep embedding was walked by `doParse` at every step; here each combinator is its clause. Defunctionalization turns the closures into a sum, and each apply whose constructor is known folds to a direct call (0004 §2.7). The `assert_total` marks say where upstream's interpreter asserted the same recursion. |
| the context table on a growable `Linear.Array` | Written in place, grown by doubling, where upstream copied an `IOArray` 10000 slots longer at each fill. 0003's stage 1 ports it to `Linear.Vec` over `LArray` (0003 §3.8, D19); it stays an improvement. |
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
| a TTC's local variable decides its `IsVar` proof from the scope (`isVarAt`) | a walk of the scope for each variable read | 6, whose first case admits upstream's forged proof where it is used only at quantity 0; else measured on the TTC load |
| a scope coercion is a traversal (`embedTerm`, `compatTerm`, `map embed`); `Cast (Doc Void) (Doc ann)` rebuilds the document | a rebuild of every node | `idr-identity` in 0004's inner per-function pipeline (0004 §4.6); a stage checks with `idr-expect`'s `not-called` that each call is gone |
| `Libraries.Text.Token`: `match` gives text, each user converts | the token's value typed by its kind | 3 (D11) |
| `Libraries.Text.Lexer.Tokenizer.Compose`: the tag a `String` | a typed tag; string comparisons | 4 (D11) |
| Levenshtein over lists of rows | an array | `Linear.Vec` over 0003's `LArray`, after 0003's stage 1, if the bench shows the cost |

## What the cutover settled

The cutover took the handoff's diet, and part of it is what these
features would have built. *Read* (the built frontend: nothing below is
emitted any more):

- **No quantity zero reaches the dialect.** An erased parameter, field,
  argument, capture or binder is not emitted, and the erased grade is gone
  from the dialect. Where an erased value sits in a runtime position the
  frontend cannot drop, it refuses with `unsupported (type)`, naming the
  term and its head (`Terms.idr:130-137`). Features 3 and 5 compile those
  refusals where the set is bounded; until then the refusal is the
  precise message the bar asks for.
- **No newtype.** A data type with one constructor and one runtime field
  is its field. The ledger's "a scope coercion is a traversal" rows lose
  their constructor cost here, before `idr-identity` sees them.
- **Saturated methods and arity.** A method whose implementation the
  instance fixes is one direct, saturated `idr.call`, and a definition is
  emitted at its syntactic arity. That is the bounded case of the
  evidence above, now emitted as direct code rather than recovered by
  specialization.
- **A forced constructor's erased variable is the runtime field it equals**
  (6aa2b517, `Translate/Forced.idr`). That is the representational half of
  feature 1; the match on the index replacing the match on the proof is
  still to build, and today it is the `match` refusal of
  `Cases.idr:534-539`.
- **Readable names.** A symbol is its instance key printed; a feature's
  sums read in a dump as the types they are for. What the pipeline
  generates is named from content, the owner and a hash of the structural
  key (0004 §4.1, D18).

## Where it sits in the self-host plan

Self-hosting comes first (0002 §2). Steps 1 and 2 are done; step 3's
record is 0004's F0, and the wall is 0004's pipeline cutover, which takes
0006's S2 (split LLVM codegen) inside it (0004 §5.4, lane L7). Steps 4 to
6 follow the cutover: the diet and the memory (a record), `make self`
(stage 2 byte-identical to stage 3, every stage byte-identical at 1, 2
and 8 threads), and the test runner off Chez. Then, in queue order,
0003's stage 1 and sharding. None of that needs a feature here: the fork
compiles as rewritten.

*Decision:* this proposal's stages may start any time after `make self`
(0002 §2 step 5), as 0002 and the proposals index say; nothing waits on
them. Each lands only if the native self-compile is no slower for it. A
change that edits what 0003's stage-1 cutover edits waits for that
cutover, which is one change with `make self` green across it; of this
file's work that is only the Levenshtein row and the context table. The
six features edit the frontend's translation of instances, types,
dictionaries and matches, beside the array translation 0003's stage 1
replaces (0003 §15). Feature 6 does not wait for 0007's interned names
(D8).

## The bar: no runtime price, decided at compile time

*Decision:* every feature here is compiled away. None of them may introduce
a uniform (boxed) representation, a runtime type code dispatched on at
each use, a dictionary passed at runtime, or an indirect call that the
monomorphic code does not have. Code that uses a feature must run at
least as fast as the code it replaces, on the bench and on the
self-compile, and use no more memory; a replacement that is slower is not
taken. What makes this possible is the one fact this compiler always has:
the whole program, which is the unit of meaning (0004 §1). Every set the
features need (the types an existential is built at, the kinds a
dependent result is computed from, the types held at runtime) is finite
and known at compile time, so each runtime choice becomes either a
specialization or a closed sum whose variants are exactly the program's
cases. 0004's optimizer then folds and specializes that sum like any other
data: case of known constructor, specialization on known constructors
(0004 §2.7, §4.6, §4.8). Where a set is not finite (a type that grows
without bound at runtime), the program is refused with a message that
names the growing value, never boxed.

## The features, each as a compile-time construction

Roughly in order of cost (*conjecture*). *Decision:* each is built in the
frontend (classification, instances, representations), which holds the
whole program's types and decides every set below (AGENTS.md: Idris does
types). What it emits is ordinary `idr` data and calls, which 0004's
pipeline compiles like any other; no pass of 0004 has a case for any of
these features, since a C++ branch per feature is what the
representation rule forbids. Static normalization (0007's A3) will find
more values known in the frontend, where the instance is decided.

1. **An erased match forced by a runtime value.** A match on an erased
   proof (`First`, `Later`) that a runtime index determines is compiled as
   the match on that index, the detagging Idris's own backends do: the
   proof's constructors map to the index's, decided per data type from its
   constructors' indices, which is the view `Translate/Forced.idr`
   already computes. No runtime cost: it is the match the fork now writes
   by hand. Where Idris accepted the match, its alternatives are told
   apart by forced indices (*conjecture*, checked on every erased match
   in base, the fork and the corpus). *Decision:* once the stage's check
   holds, a match that is not told apart is an internal error, a broken
   invariant (0004 §2.5), not a refusal; until then it stays the `match`
   refusal, which names the runtime value to match on. The same stage
   compiles a match on `Delay` as a force bound to its variable, which is
   upstream's meaning of it (the table above).
2. **Polymorphic recursion, bounded.** A group of definitions that calls
   itself at other types or implementations (a `Functor` method calling
   `map` through the implementation at a type it binds; a nested datatype
   such as a finger tree) has, in the whole program, the instance set the
   frontend's worklist reaches (`Instances.request`,
   `Instances.idr:100-118`). When it is finite, each instance is
   monomorphic and every call direct; when it grows, the program is
   refused naming the type that grows.
   - **The rule** (*decision*). The worklist decides finiteness itself, on
     each request chain: an instance, the instance that first requested
     it, and so on back to `main`, which `growing` already walks
     (`Instances.idr:62-92`). A new instance of a definition is refused
     when, against an ancestor instance of the same definition on its
     chain, its static arguments (types, implementations, and the shapes
     `neededShape` keeps, `Instances.idr:163-181`) are smaller in no
     position and larger in one, by the size of their normal forms, a
     literal counted by its magnitude. The refusal names the definition,
     the argument and both keys. That is the megamorphic case: a
     recursion that builds its type deeper at each call.
   - **Why it is total** (*conjecture*, checked by the stage's tests).
     On one chain the instances of one definition have distinct keys,
     and finitely many keys share one vector of sizes. By Dickson's
     lemma, an infinite sequence of size vectors has an infinite
     non-decreasing subsequence; it must grow somewhere, and there the
     rule refuses. So every chain is finite, and the request tree,
     finitely branching, is finite (König's lemma). The worklist ends on
     every program, which is what the budget guarded.
   - **What it deletes** (*decision*). The blanket refusal of
     `checkComponent` (`Recursion.idr:139-152`), which refuses any
     changed static argument, bounded or not; and `instanceBudget` with
     its `compile-time budget` refusal (`Instances.idr:32-39, 110-112`),
     which exists for calls Idris's size-change graphs do not record
     (under `assert_total`, or through a local function, as its comment
     says). The rule reads the worklist's own requests, which see every
     call. The loop verdicts `checkComponent` computes stay. This is
     0004's rule applied to the frontend: no budget decides acceptance.
   - **What it refuses that is bounded:** a recursion that builds a
     larger static argument once and is stopped by a type-level match,
     with no argument getting smaller. It is refused by name; no budget
     would tell it from one that never stops, and its shape is the one
     AGENTS.md calls megamorphic. The precedent is the well-quasi-order
     test that stops supercompilation (*recalled*: Sørensen, Glück and
     Jones, `papers/sorensen-1996-positive-supercompiler`, not re-read).
   - Not a reason to bring back the frontend's nested `Term a`: its
     `Fin n` form is the better representation (the ledger).
3. **A result or field type computed from a runtime value**
   (`tokValue : (kind : k) -> String -> TokType kind`, `ActType`).
   - Where the value is known at the call (a literal kind, a constructor
     in the argument's shape), the instance is specialized on it, as
     `neededShape` already specializes on a parameter's shape
     (`Instances.idr:163-181`): the result type reduces and the call is
     monomorphic. Static normalization (0007) will find more of the
     value in the frontend, and 0004's specialization on known
     constructors (0004 §4.8) extends this across calls.
   - Where it is not, the type is the closed sum of the type's whole-
     program image: `TokType` over the kinds is a finite set of types, so
     the result is a sum with one variant per image type, tagged by the
     value it was computed from. A match on the value at the use refines
     the type in each branch to one variant: the frontend emits the
     sum's match with that arm alone reachable (Idris proved the others
     impossible), and canonicalization turns it into the variant's
     payload with no test. A field type computed from another field is
     the same sum inside the data's layout (proposal 0009's flattened
     layouts place it), so `ActType`'s action is stored unboxed.
   - **The image** (*decision*) is computed in the frontend from the type
     function itself, never from a flow analysis of runtime values, which
     would be a second label analysis beside 0004's. Over an index type
     with finitely many values (an enumeration, such as `TokType`'s
     kinds) it is the normal form at each value, which is exact. Over any
     other index type it is the language of the type function's clauses
     read as a grammar, a recursive call standing for the whole image; it
     is finite when no recursive call sits under a type constructor (a
     regular tree grammar, whose finiteness is decidable, *recalled*).
     Where the image is infinite and the value unknown at the call, the
     type's set is unbounded: the program is refused as megamorphic,
     naming the type function and the value (`Ints` of
     `polymorphism-growing-shape` has such an image).
   - **The sum** (*decision*) is an ordinary `idr.data`, one constructor
     per image type, its tag written from the value where the result is
     built. Reason: an untagged union whose discriminant is another value
     would be a second kind of sum in the dialect, one concept held
     twice; whether the tag shares storage with the value is a layout,
     0009's to choose by measurement. A non-recursive sum is unboxed,
     and its tag is as wide as its count needs
     (`foreign/idr/lib/IR/OpsData.cpp:91-92`, *read*).
4. **Existentials** (`SeqEat`, a tokenizer's hidden tag, a hidden name
   type, a constraint field). A constructor that hides a type or holds an
   implementation is, in the whole program, built at finitely many types
   or implementations: its witnesses. The hidden value becomes a closed
   sum over them, exactly as defunctionalization turns a closure's
   captures into a sum with one constructor per label (0004 §2.4); an
   implementation that closes over runtime values carries those values
   in its variant. The operations used on the hidden value become a match
   on the variant, which specialization and case of known constructor
   remove wherever the construction site reaches the use (the parser
   combinators: every grammar is a constant, so most collapse to direct
   code). No box, no vtable.
   - **How** (*decision*). The frontend generalizes the constructor's
     dictionary table (`Dictionaries.idr:135-157`) from one
     implementation per field to the set of witnesses the program
     builds. The set is a monotone relation filled by the instance
     worklist: each match on the constructor requests its alternative
     once per witness, as an instance keyed by the witness, so a new
     witness is a new request, never a restart. Today a construction
     site met after a match voids the pass, and translation starts over
     from `main` (`Dictionaries.idr:22-30`;
     `Translate/Programs.idr:126-136`, *read*); that resume loop goes
     with the one-implementation rule.
     0008's O3 is the same fixpoint as tables (0008 §4.8).
5. **Types at runtime** (`KeyVal` holding a `Type`, a match on `{a =
   Name}`). *Decision:* built, last, as feature 4's relation for a field
   or argument with no payload. A `Type` held at runtime is a witness
   with nothing beside it, so its value is a constructor of the closed
   sum (an enumeration) of the types the program stores there, and a
   match on it is a switch, folded at compile time wherever the type is
   known (always, for `WithData`, whose field lists are constant). A
   partial application missing a type parameter is the same value
   passed late. Reason for building it: the end state above refuses only
   megamorphic constructs, and a `Type` held at runtime is bounded.
   `WithData` stays concrete records, which are better (the ledger).
6. **Equality a primitive decides, with its proof.** Base decides
   `DecEq` for strings, integers and the other primitive types with the
   primitive and forges the proofs (*read*:
   `third_party/Idris2/libs/base/Decidable/Equality.idr:138-145`,
   `primitiveEq = believe_me (Refl {x})` and `primitiveNotEq prf =
   believe_me {b = Void} ()`). That is why the fork's equality proofs
   went: the profile refuses every `believe_me` but the exit's
   (`compiler/src/IdrisMLIR/Frontend/Profile.idr:274`,
   `Translate/Terms.idr:868-871`, *read*).
   - **The rule** (*decision*). In a trusted library (base, and the fork,
     which this compiler trusts as it trusts base: `compiler/idris/
     README.md`), a `believe_me` is accepted in three cases, each one
     where the coercion cannot make a runtime value wrong, because the
     representation leaves nothing to be wrong:
     - its result is used only at quantity 0, so it is no value of the
       module (the frontend emits no erased value);
     - its target's representation has one value: `Equal x y` is one data
       instance whatever its indices, one constructor and no runtime
       field (`third_party/Idris2/libs/prelude/Builtin.idr:123-125`;
       HANDOFF.md, 2026-10-10: a type parameter named only in erased
       fields keys no data instance), so the proof in `Yes primitiveEq`,
       unrestricted in `Dec` (`libs/prelude/Prelude/Types.idr:267-274`
       there), is that one value;
     - its target has no value (`Void`): the body is unreachable.

     Anywhere else, and in user code always, it stays an escape hatch.
     Compiled, `decEq` is the primitive's test alone.
   - The fork's `nameEq`, `scopeEq` and the rest then come back as
     upstream wrote them, at the cost of the comparison they already
     make, and the proofs retype terms where the fork now rebuilds them.
     The comparison's own cost, strings compared by traversal, is 0008's
     O1 over 0007's interned names (A0); under them `nameEq` decides by
     id with the same rule.

## Staged plan

Each stage is one feature, in the order above, but 5 lands right after
4, whose relation it reuses, and 6 may land at any point after `make
self`, since it touches only the profile's rule and the fork's equality
code. Each stage has:
- its tests: programs with expected output; each reject fixture the
  table above assigns to the feature moved to `tests/programs` or
  `tests/accept` with its expected output; reject tests for the
  unbounded cases with their precise messages; and an `idr-expect`
  property that in `@f` no match on a constructor known at compile
  time, no closure and no indirect call is left where the value is known
  (`no-closures` exists; the rest is one property, added with feature 1
  and stated once, tests/README.md), never a match on op sequences;
- the regressions in the ledger it replaces, replaced in the same change;
- `make test`, `make test-idr` and the emitted corpus unchanged except
  where the feature turns a refusal into a program by design; `make self`
  green, stage 2 byte-identical to stage 3, every stage byte-identical at
  1, 2 and 8 threads;
- the bench and the native self-compile, old binary against new under
  identical conditions (0004 §10): no slower beyond the run-to-run
  spread, no more memory, or the replacement is not taken and the stage
  says why.

## Measures

- Runtime: the bench and the native self-compile, the code that uses a
  feature against the code it replaces; the bar is "no slower".
- Compile time: the extra instances and sum variants each feature makes,
  recorded per stage (a record, never a refusal), and the native
  self-compile's wall time and peak resident memory, first recorded at
  `make self`. No native figure exists yet. The Chez stage-0 run (137 s
  at 9.1 GB peak, c50d176d; about 140 s in 0004's F0) measures Chez and is
  not the bar. The "87 s, 1.8 GB on stage 0" this file once gave was
  written at 4c87ad0f, half an hour before stage 0 first compiled the
  whole frontend at c50d176d, and is superseded by it.

## Decisions

- D1 (the user's, 2026-10-10). The three rules at the top.
- D2. The bar: every feature compiled away, no runtime price, decided at
  compile time.
- D3. Of the constructs inside the language, only megamorphic ones stay
  refused; what is outside the language stays out. No bound on a sum's
  variants. A boxed sum past the runtime header's 2^16 tags
  (`runtime/idris_rt.h:106`, refused at `OpsData.cpp:93-98`) is a layout
  limit, 0009's ground, not a bound on the program.
- D4. Feature 2's rule on request chains; it deletes `checkComponent`'s
  blanket refusal and the instance budget.
- D5. Feature 3's image comes from the type function's clauses; its sum
  is an ordinary `idr.data`.
- D6. Feature 4 is a monotone witness relation in the instance
  worklist; the dictionary restart goes.
- D7. Feature 5 is built, as feature 4's relation without a payload.
- D8. Feature 6's three cases for `believe_me` in a trusted library; it
  does not wait for 0007's A0, and the churn when A0 lands is accepted
  (0004 D5).
- D9. Every feature is built in the frontend; no pass of 0004 has a case
  for one.
- D10. A variant keeps its payload's quantity in its type (`!idr.lin<T>`
  for quantity 1), which the verifier checks after every pass as it does
  every field; a quantity-0 payload is no field; ownership grades are
  `idr-rc`'s whole-program decision, made on the sum as on any data
  (0004 §1). Reason: AGENTS.md keeps quantities in types so that no pass
  can drop them, and a feature's sum is data like any other.
- D11. `TokenKind` comes back with feature 3, and the `Compose` tag with
  feature 4, each as its stage's proof on real code, if the bar holds;
  otherwise the rewrite stays, by D1's first rule.
- D12. The stages start after `make self`; a change to what 0003's stage
  1 edits waits for it.

No question is open. The three this file held are decided: the bound on
a sum's variants (D3: none), how a sum meets layouts and grades (D5,
D10), and whether `TokenKind` comes back (D11).
