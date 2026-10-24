# Rederivation audit: constants and statically known values

Family: literals, computed constants, guards' decisions, intervals and
ranges, the values a type or a key fixes, and static data, traced from the
checker and the frontend's keys through Emit's literals, the e-graph,
idr-constants (being deleted by D132), the guards (C285), the range
analysis and narrowing (Narrow), the lowering, and the runtime's tests of
values the compiler knew (bounds, zero divisors, sizes).

- HEAD at start: `b2aab6e9ba40e43debc690277bf1eeda58adcfac`
- HEAD at finish: `d73863f5e4377ce21574b94896868b12f9403fe9` (D133's design
  and C289 landed during the audit: `proposals/` and a handoff only; no site
  below changed)
- Ground: everything is **read** from source unless a line says
  conjecture. Nothing was measured: this machine has no built C++ tool or
  frontend, and no build was attempted. A cost is the shape of the work (per
  op, per query, per function, per run), not a number.
- In flight in the checkout: D132's deletion of idr-constants
  (`Transforms/Effects/Constants.cpp`, `Analysis/Constants.{h,cpp}` deleted;
  the e-graph, `Optimize.h`, `Optimize.cpp`, `Settle.cpp` modified; `PINS.md`
  being edited); C286 in Emit (`Emit/Bodies.idr`, `Emit/Operations.idr`,
  `Emit/Monad.idr` modified) and in the frontend's translation (`Types.idr`,
  `Instances.idr` modified); L04's `IR/Families/Refinement.cpp`. Each finding
  says which of its files are modified now.
- Covered by sibling reports and not counted again: a static datum's global
  named and found by a content digest (identities-names 5 and 6);
  `fitting`'s per-slot type comparison (types-layouts 8); a numeral constant
  kept as successor cells (types-layouts 9); `exit`'s status tested where
  it is a constant (effects-termination 7).

---

## 1. Narrow's per-function range solve is made three times; two are thrown away

**The fact.** The integer interval of every value of one function under the
program's summaries (what each function returns, what each is passed).

**First known.** The arguments phase of the `Ranges` analysis, callers
first: each function is solved under its final summaries
(`foreign/idr/lib/Analysis/Ranges.cpp:236-286`, the solve at `:260`), to
learn what it passes each callee of another component.

**Dropped.** At the end of that lambda: `solved` is a local, read for the
call operands it passes (`:262-284`) and destroyed. `Ranges` keeps only the
summary rows (`include/idr/Analysis/Ranges.h:100-101`).

**Re-derived.**
- `idr-narrow` solves every function again under the same summaries on the
  same IR, to version its loops (`Transforms/Narrow/Narrow.cpp:209-219`, the
  solve at `:212`): the same answer as `:260`.
- `idr-narrow-words` solves every function a third time
  (`Narrow.cpp:84-96`, the solve at `:91`) and reads the solve into a dense
  table (`Facts::read`, `include/idr/Transforms/Narrow.h:229`,
  `IndexVector<ValueId, ranges::Bounds>`); where no loop was versioned the IR
  and the summaries are the ones `:260` solved.
- Where any loop is versioned, the whole analysis runs again for every
  function (`Narrow.cpp:222-231`): two more solves each, the second again
  repeated by `idr-narrow-words`.

Each solve is a fresh `DataFlowSolver` loading dead-code analysis, constant
propagation and the integer range analysis over the whole function
(`Ranges.cpp:176-191`), state per value at upstream's size. Per function: 4
solves where 2 differ (returns phase, arguments phase); 6 where 3 differ
once a loop is versioned.

**Carrier.** The one solve under final summaries, read once into the table
`Facts` already makes (`IndexVector<ValueId, Bounds>`, sized by the
function), at the arguments phase; versioning and the word rewrite of that
function read it there. Versioning keeps what the function passes sound (the
original loop's operands cover both versions), so it can run in the same
callers-first step, and the analysis is decided once. "A fact is computed
once and kept": an analysis result, in the analysis manager, sized by the
problem.

**Deletes.** `Narrow.cpp:89-96` and `:209-219` (the re-solves and their two
"internal error: the range analysis failed" paths), `:222-231` (the second
analysis) once versioning runs inside the schedule; `Ranges::Solved` and
`Ranges::solve` as public API (`Ranges.h:57-80`), `boundsOf(const
Ranges::Solved &, ...)` and `Facts(FuncOp, const Ranges::Solved &)`
(`Narrow.h:59, 173, 229`) reading a solver. About 50 lines; 2 of every 4
solves per function.

**Owner and waits.** L14 (`Analysis/Ranges.cpp`, `Ranges.h`), L12
(`Transforms/Narrow/`). Checkout: all clean. Waits on nothing.

**Confidence.** Read (the three solves, the same summaries, the same IR).
The share of compile time is conjecture.

---

## 2. A natural the compiler knows (a literal, or the shape that keys its instance) loses its value at every slot it fills

**The fact.** The value of a natural fixed at compile time: a numeral Idris
wrote, or a runtime parameter "whose argument's shape keys the instance"
(`Frontend/Translate/State.idr:233-235`).

**First known.**
- A literal: `Emit/Operations.idr:265` types it `!idr.nat<k>` (`NatT (INat
  k)`), the type the dialect says *is* that natural ("where its index term
  is a closed natural it is that natural: the one place a natural's literal
  is said", `IR/TypeLiterals.cpp:51-63`).
- A key: `Frontend/Translate/Instances.idr:705-708` keys the instance at the
  argument's shape; the frontend reads it to rule out the zero or the
  successor arm and to give the predecessor its own shape
  (`Translate/Cases.idr:348, 758-779`), so in the copy keyed at 3 it knows the
  predecessor is 2 and keys the recursive call there.

**Dropped.**
- The parameter's type: `runtimeTypeOf` (`Instances.idr:458-462`) reaches
  `dataTypeIn`, which gives every natural `NatT IOpaque`
  (`Translate/Types.idr:888`), the shape-keyed parameter included. The core
  type's own statement says `NatT` holds "the level of a binder that is both
  a value and an index" (`compiler/src/IdrisMLIR/Types.idr:135-139`); no
  `NatT` with a level or a key's number is built anywhere in the frontend
  (`IVar` is built only for families' indices, `Types.idr:134`,
  `Choices.idr:527`).
- The argument: `operand1` (`Emit/Bodies.idr:141-146`) fits every operand to
  its slot; `!idr.nat<3>` against `!idr.nat<_>` is a reindex
  (`Emit/Tensors.idr:175, 186-191`).
- The reindex folds no constant: `DataReindexOp::fold`
  (`IR/Families/Refinement.cpp:113-123`) folds only a reindex to its own type
  and a reindex of a reindex; the op has no range interface
  (`Spec/Families/Ops.idr:233-245`), and the e-graph has no rule for it.

**Re-derived, or paid at run time.** No reader recovers it. Upstream's
constant propagation and `Ranges` see the reindex as an unknown natural,
seeded at `[0, ∞)` (`IR/Ranges.cpp:150-157` reads a natural's reading,
never a closed index); the e-graph's leaf holds no facts
(`Transforms/EGraph/Nodes.cpp:272-275`); the specializer's `constantOf`
(`Specialize/Patterns.cpp:30-35`) and the callee summary
(`EGraph/Simplify.cpp:44-60`) match `m_Constant` and miss it. So a copy
keyed at a closed shape computes at run time what its key fixed: the
predecessor by `idr.nat.pred` (`Emit/Bodies.idr:746`) and the argument passed
on, at every call of the chain, every run. Where the value is kept it is
kept twice, in the type's index and in the `#idr.big` attribute, which
`NatType::isLiteral` holds in step (`TypeLiterals.cpp:59-62`): a copy kept in
step by a verifier.

**Carrier.** The type. A parameter its key fixes to a closed natural is
`!idr.nat<k>` in the instance's signature (the frontend's `ValueParam`
takes `NatT (INat k)` where the shape is a closed numeral); a value of a
closed natural type is that constant to every reader (`ranges::ofType`
gives the one value, the e-graph's leaf and constant propagation start
there), and the instance materializes it, or the parameter leaves the
signature: the specialized entry point AGENTS.md names. And a constant
reindexed to a type that admits it is that constant: one fold arm through
`fold::held`, the statement of where `idr.constant` stands. Both are
upstream's grain: a fold is an op's meaning; a closed type parameter is a
type fact.

**Deletes.** One `idr.data.reindex` per natural literal at a call,
constructor or return slot (a literal built at its slot's type through
`fitted`, `Tensors.idr:221-223`, instead of `fit` after it); the run-time
`idr.nat.pred` chain and the passed parameter in every shape-keyed copy; the
attribute-and-type double statement (which copy goes is the owner's: a
closed natural's constant holds its value once). Few lines; run-time work
in every keyed copy.

**Owner and waits.** L16 (`Translate/Instances.idr` M, `Translate/Types.idr`
M, `Emit/Operations.idr` M, `Emit/Bodies.idr` M, `Emit/Tensors.idr`), L04
(`Refinement.cpp` M, `TypeLiterals.cpp`), L13 (`IR/Ranges.cpp`), L14 (the
e-graph's leaf, M). Waits on L16's C286 hunks and L04's `Refinement.cpp`
hunk. Which op holds the constant is a core shape: the owner's.

**Confidence.** Read: each drop, the missing fold arm, that no reader reads
a closed natural index. No fixture holds a closed `!idr.nat<k>` (`git grep`
over `tests/`: none), so no test sees the reindex. The run-time cost is
conjecture.

---

## 3. A big constant crosses between its attribute and the runtime by decimal text

**The fact.** The integer a `#idr.big` holds, as the runtime represents it
(its small word, or a bignum's limbs), and whether it is small.

**First known.** The attribute's `APInt`, binary, written by the frontend
(`Emit/Operations.idr:264-265`) or by a fold.

**Dropped.** `fold::bigOf` (`IR/Fold/Scope.cpp:50-58`) prints the `APInt`
as decimal, makes a runtime string of the text, and parses it with
`big.from_str`; `fold::bigAttr` (`Scope.cpp:64-71`) prints the runtime big
with `big.show` and parses the text into an `APInt`. The binary value is
thrown away at each crossing and read back from its decimal form.

**Re-derived.** Per crossing, a print, a parse and two runtime allocations
(a string cell; a bignum past the small range):
- every attribute fold reading a big operand (`Fold.h:220-221`, through
  every `RuntimeFolds` op and the guards' `decide`, `Ops/Guards.h:66`);
- every big an op holds that the e-graph reads (`EGraph/Values.cpp:561`)
  and every big it writes back (`:613`), and every attribute fold's big
  result (`Fold/Values.cpp:103`);
- the lowering: each big datum, made into a runtime big only to copy its
  limbs out (`Conversion/StaticBytes.cpp:103-116`), and each use of a big
  constant, made into a runtime big only to ask whether it is small
  (`StaticBytes.cpp:133-140`), which the `APInt` says (its significant bits
  against the small range, `IR/Ranges.cpp:24-29`'s `inside`).

The comment at `StaticBytes.cpp:98-99` gives the reason as "one semantics
for what a big literal denotes, the fold's: big.from_str's"; but the
attribute's `APInt` is the integer, and printing it and parsing it back is
the identity: no semantics is chosen.

**Carrier.** The integer's own words. A small one is its word
(`idris_rt_small_word`), built directly where the `APInt` is in the small
range; a large one is its limbs, as `StaticBytes.cpp:117-130` already lays
a bignum out, read from and into `APInt`'s words (`APInt(bits,
ArrayRef<uint64_t>)`, `getRawData`). The runtime's ABI states the bignum's
layout once (`idris_rt.h`).

**Deletes.** The text round trips in `Scope.cpp:50-72` (replaced by word
copies), the runtime big made per datum in `StaticBytes.cpp:103-116` and per
use in `:133-140`. About 30 lines; a print, a parse and two allocations per
big read or written, at every fold, e-graph read and lowered use.

**Owner and waits.** L13 (`IR/Fold/`), L21 (`Conversion/StaticBytes.cpp`),
L14 (`EGraph/Values.cpp` M), L11 if the runtime gains a limbs entry. Waits
on L14's D132 hunks in `EGraph/Values.cpp`.

**Confidence.** Read.

---

## 4. Intervals are carried by no representation: every engine starts from nothing, and LLVM is told none of a function's

**The fact.** The interval of a value, and of each function's parameters
and results.

**First known.** The e-graph, per class, every run
(`EGraph/Nodes.cpp:345-405`): at every round of idr-optimize's inner
pipeline, after `columns` and after `bufferize`
(`Spec/Pipeline/Pipeline.idr:597, 601`), and for a final callee at its last
round.

**Dropped.** The write-back places constants only
(`EGraph/Elaborate.cpp` holds no interval), and a final function publishes
the constant ops it returns and nothing of their intervals
(`EGraph/Simplify.cpp:44-60`). No interval reaches the IR or a summary.

**Re-derived.**
- `Ranges`' returns phase solves every function again, callees first, to
  learn what each returns (`Ranges.cpp:199-236`, read by
  `visitExternalCall`, `:120-135`), one full solve per function.
- Finding 1's solves.
- The lowering re-infers each runtime call's range with every operand at
  its widest (`Conversion/RuntimeCalls.cpp:40-56`, `statedRange`), per call.
- A function's parameter and result ranges never reach LLVM: the lowering
  states only a tag's range from its type (`Conversion/Lower/Functions.cpp:96-110`)
  and an op's operand-free range (`RuntimeCalls.cpp:175-181`), so LLVM's own
  value-range analyses derive them again.

**Carrier.** An interval is a fact of the program's meaning, which every
later pass keeps, so one computed once stays sound (possibly wider than a
later solve finds). A function's parameter and result intervals as an
inherent property of `idr.func`, the summary row `Ranges` keeps in its
`Ragged` tables (`Ranges.h:100-101`), written once by the one interval
engine; lowered to LLVM's `range` on parameters, results and call results.
Never a discardable attribute (AGENTS.md).

**Deletes.** The returns phase (`Ranges.cpp:199-236`) and the `returns`
table where the e-graph's final-round intervals are published; LLVM's
re-derivation (no lines of ours). About 40 lines and one solve per function.
The arguments phase stays: the e-graph sees no caller.

**Owner and waits.** L14 (the e-graph M, `Ranges.cpp`), L02 (`idr.func`,
`Spec/Functions/`), L21 (the lowering), L12 (Narrow). Waits on L14's D132
hunks. Which op holds the fact is the owner's.

**Confidence.** Read for the drops and the re-solves; conjecture that the
optimizer's published intervals are tight enough to replace the returns
phase after inlining, columns, bufferization and counting.

---

## 5. A literal match's case facts: known by the frontend, kept by no value, read by two readers two ways and by the guard decider not at all

**The fact.** In a case of a literal match, the binding is the case's key;
in the default, it is none of the keys. Emit's own comment states the
purpose: "what a case proved of it (a divisor matched against `0`) stays
known where the default reads it" (`Emit/Bodies.idr:694-703`).

**First known.** The frontend, from Idris's constant alternatives
(`Emit/Bodies.idr:704-727`).

**Dropped.** `rebound` (`Emit/Bodies.idr:225-233`) binds each region's
scrutinee at the scrutinee's own type, and the value's refinement holds
data tags only (`Emit/Monad.idr:104`, `AnyConstructor | OneOf`): nothing
states a case's key or a default's exclusions on the binding.

**Re-derived.**
- `LitMatchOp::getRegionScrutinee` (`IR/Control/LiteralMatch.cpp:61-69`)
  from the key array, read by identities (`Analysis/IdentitiesRecord.cpp:74-85`).
- `Ranges` restates it by `dyn_cast<LitMatchOp>` and not through that
  interface (`Analysis/Ranges.cpp:31-52, 89-118`), with `excluding` and
  `cut` (`IR/Ranges.cpp:46-75, 173-215`), per region entry per solve (4 to 6
  solves per function, finding 1). An interval cuts a key only at an end, so
  "not 0" of a signed scrutinee is not even expressible there.
- The e-graph, the one place guards are decided (`GuardDecided`), joins the
  scrutinee's facts into each region's input (`EGraph/Regions.cpp:21-28`)
  and reads neither form. A guard on the default's binding (the divisor of
  Emit's comment) is never decided and is tested at run time
  (`Conversion/Checks.cpp:44-52`).

**Carrier.** The frontend's refinement. In a case of a word or `Char`
scrutinee, which carries no count, the binding is the key constant itself;
a counted scrutinee keeps its region argument for the move. The value's
refinement gains the default's exclusions beside `OneOf` tags, and Emit's
guard builder (`specGuarded`, `Emit/Operations.idr:113-119`) writes no guard
its operand's refinement decides: "a proof is the absence of the guard"
(`Spec/Ops/Checks.idr:13-17`). What stays for intervals is read through
`getRegionScrutinee`, the op's one statement.

**Deletes.** `Ranges.cpp:31-52, 89-118` (the special case), `IR/Ranges.cpp`'s
`excluding` and `cut` if nothing else reads them (about 65 lines), and the
run-time tests of guards a match already decided. About 115 lines.

**Owner and waits.** L16 (`Emit/Bodies.idr` M, `Emit/Monad.idr` M,
`Emit/Operations.idr` M), L14 (`Ranges.cpp`, `IdentitiesRecord.cpp`), L13
(`IR/Ranges.cpp`), L09 (`LiteralMatch.cpp`). Waits on L16's C286 hunks.

**Confidence.** Read (the drop, the three readers, the e-graph's join). That
user code reaches such a guard often is conjecture: the Prelude's `div`
tests `y == 0` through a `Bool`, not a literal match (see Considered).

---

## 6. A guard's verdict is in no type: every guarded op's fold and every speculation query decides it again

**The fact.** That a guard's condition holds of its operand, so the total op
past it may compute; and a builder's guarantee of the same kind (a
`NeverEmpty` string, a matched successor's predecessor).

**First known.** The guard op (its `decide`, C285), or the frontend's
omission of it: "a partial primitive is a guard and a total op ... a proof
is the absence of the guard" (`Spec/Ops/Checks.idr:13-17`). A builder's
guarantee at the builder (`NeverEmpty` trait); a successor's at the
natural match (`Emit/Bodies.idr:731-746`).

**Dropped.** The guard's result is typed as its operand (`Emit/Operations.idr:91-101`,
`unguarded (At l) x.type`), and a refuted guard passes its operand's
interval through: "where it leaves nothing the guard always crashes ... so
the range stays as it was" (`IR/OpsChecks.cpp:154-168`), and `check.nonzero`
of zero alone keeps `[0, 0]` (`:172-189`). So a class past a refuted guard
still holds the failing constant.

**Re-derived.**
- `GuardedOp::guardsHold` (`IR/Traits.h:170-189`), asked by every guarded
  op's fold, in the attribute instance (`IR/Fold.h:229-238`,
  `IR/Numeric/Trait.h:74-81`) and the e-graph's (`EGraph/Values.cpp:248-257`):
  each guard's condition decided again on the total op's own operands. It is
  load-bearing only because of the interval hole above.
- `GuardedOp::getSpeculatability` (`Traits.h:191-212`), per query: matches
  the operand's defining op to the same guard op with equal other operands,
  else decides the guard again on constants; data dependence already keeps
  a total op below an undecided guard.
- `GuardRepeated` (`IR/Ops/Rules.cpp:94-101`) states the same structural
  match a second time.
- `neverEmpty` (`Ops/Rules.cpp:30-52`) walks an append tree per query for
  what each builder guaranteed; `NatPredOp::foldable` (`IR/OpsBigs.cpp:228-233`)
  tests a constant for zero the match before it excluded.

**Carrier.** The verdict is the guard's absence (the specification's rule),
and a refuted guard gives no value: no interval, so nothing computes past
it before `GuardDecided` makes it a crash. Then `guardsHold` is dead in both
instances and a total op whose only precondition is its guards is always
speculatable. For our own types (`!idr.str`, `!idr.big`, `!idr.nat`) a
guarantee such as "not empty" or "not zero" can be a type parameter the
total op's operand constraint requires; `i64` and `f64` are upstream's
builtin types and cannot carry one, so the structural match stays essential
for words. Which type holds it is the owner's.

**Deletes.** `GuardedFold`, `guardsHold` and their callers (`Traits.h:170-189`,
`Fold.h:162-169, 231-233`, `Numeric/Trait.h:76-81`, `Values.cpp:254-255`),
`getSpeculatability`'s body (to one line), `NatPredOp::foldable`; for our
own types, `GuardRepeated` and `neverEmpty`. About 75 lines; a structural
match per speculation query and a guard decision per fold.

**Owner and waits.** L03 (`Traits.h`), L13 (`OpsChecks.cpp`, `OpsBigs.cpp`,
`Ops/Rules.cpp`, `Fold.h`, `Numeric/`, `Spec/Ops/`), L14 (`EGraph/Values.cpp`
M), L16 (`Emit/Operations.idr` M). Waits on L14's and L16's hunks; the type
refinement on an owner's ruling.

**Confidence.** Read for each site. That no pass builds a total op on an
unchecked, unproved operand (which `getSpeculatability`'s deletion needs)
is conjecture; no verifier forbids it today.

---

## 7. The range a type proves: seeded by one interval engine, ignored by the other

**The fact.** What a value's type proves of its integer: a natural is at
least 0, a numeral `Fin[3]` is 0 to 2 (`DataType::numeralBound`,
`IR/Types.cpp:264`), a closed natural is its number.

**First known.** The type, when it is made.

**Dropped.** By the e-graph at every value that enters with no op it models:
`leaf` makes empty facts (`EGraph/Build.cpp:89, 140, 212`;
`Nodes.cpp:272-275`); an operand with no facts is taken at its storage's
widest (`Nodes.cpp:395-397`), and a guard reads a natural, of storage width
0, as no integer (`Values.cpp:165-182`). `ranges::ofType` drops the closed
natural's number (finding 2).

**Re-derived.** `Ranges` seeds every entry state from the type
(`Ranges.cpp:60-72` through `IR/Ranges.cpp:147-171`); the e-graph never does.
Two engines over one function disagree on what an argument of type
`Fin[3]` or `!idr.nat<_>` may be.

**Carrier.** `ranges::ofType`, reading a closed natural's index too, as the
one statement of what a type proves, asked by both engines wherever a value
enters with no op: the e-graph's leaf facts, upstream's entry state.

**Deletes.** `guardRange`'s fallback (`Values.cpp:165-174`), which becomes
the leaf's facts; the drift between two seeds. About 10 lines.

**Owner and waits.** L14 (the e-graph M, `Ranges.cpp`), L13 (`IR/Ranges.cpp`).
Waits on L14's D132 hunks.

**Confidence.** Read.

---

## 8. Emit restates the Integer-to-Char conversion's scalar bound

**The fact.** Which integers are Unicode scalar values, and what an Integer
outside them converts to.

**First known.** The one template of inline arithmetic
(`IR/Numeric/Inline.h:109-131`, `toChar`), which AGENTS.md makes the one
meaning of "the scalar-value test, the char conversions".

**Dropped / restated.** Emit writes its own range test for a big:
`0 <= b <= 0x10FFFF` by two `idr.big.cmp`, an `arith.andi`, an
`arith.select` of -1, then `idr.int.to_char_s` (`Emit/Operations.idr:396-407`).
The bound 0x10FFFF is written in Idris and in C++.

**Re-derived.** `int.to_char_s` decides the same bound again on the word.

**Carrier.** The template: a big's conversion to `Char` is one op whose
meaning is `toChar` over the big's clamp to the word range, generated from
the specification like the word conversions.

**Deletes.** `Emit/Operations.idr:396-407` (about 10 lines) and the second
copy of the bound.

**Owner and waits.** L16 (`Emit/Operations.idr` M), L13 (`Numeric/`,
`Spec/Ops/`). Waits on L16's C286 hunks.

**Confidence.** Read.

---

## 9. D132's deletion leaves idr-constants declared by the specification

**The fact.** That idr-optimize's inner pipeline has no constants step.

**First known.** D132 ("the e-graph takes idr-constants' duties and
idr-constants goes"), being carried out in the checkout:
`Transforms/Effects/Constants.cpp` and `Analysis/Constants.{h,cpp}` deleted,
`Optimize.h` and `Optimize.cpp` no longer build the step, `PINS.md`'s three
site lists being edited now.

**Held still.** `Spec/Pipeline/Pipeline.idr:529-535` declares the
`constants` pass and its three actions, and `:566` lists it in `passes`;
the generated `IdrInnerPasses.td:33-36` declares `IdrConstants` with the
constructor `createConstants`, which no longer exists, and `Actions.h.inc:43-47`
the three action tags. A remaining reference by C251, and a build break
until regenerated.

**Carrier.** The specification alone: the record goes, the generated files
follow.

**Deletes.** `Pipeline.idr:529-535` and the list entry; the generated
declarations by regeneration. About 10 lines.

**Owner and waits.** L03 (`Spec/Pipeline/`), INT (generated files), L06
(`PINS.md` M). Waits on L14's D132 change landing with them.

**Confidence.** Read.

---

## 10. A loop's natural that only descends: found again by walking the loop (conjecture)

**The fact.** That a self-recursion's natural argument only descends, so a
version entered with a small natural stays small.

**First known.** The checker's size-change termination search
(`compiler/checker/src/Core/Termination/CallGraph.idr`), and the frontend,
which translates the self call's argument as the successor arm's
predecessor.

**Dropped.** The TTC keeps the verdict, not which argument descends
(control-calls R3 and effects-termination 2 trace the verdict itself); the
frontend writes no descent on the call; idr-tail-loops makes an `scf.while`
with none.

**Re-derived.** `descends` (`Transforms/Narrow/Versions.cpp:34-96`) walks
each loop's yields back through `idr.nat.pred`, linear casts, the condition
and every merge, per loop, matching `NatPredOp` by class rather than by its
`structural::Predecessor` (`IR/OpsBigs.cpp:247`).

**Carrier.** The descent as a fact of the self call, written where the
frontend knows it and kept by tail-loops on the loop it makes.

**Deletes.** `descends` (about 60 lines).

**Owner and waits.** L12 (`Versions.cpp`), L16 (the call), L10 (tail-loops),
L17 (the checker). Owner's ruling on what the call carries.

**Confidence.** Conjecture: whether the frontend's predecessor binding
covers every loop `descends` accepts is not established.

---

## Considered, not findings

- The runtime does not test again what a guard tested: a big divisor is not
  zero "idr-lower checks it first" (`runtime/Big/Arithmetic.cpp:107`); the
  string bounds are tested once, by the guard's lowering
  (`Conversion/Checks.cpp:58-71`) against a stored scalar count
  (`idris_rt.h:136-140`).
- Allocation sizes are constants at every call; snmalloc's size class folds
  once the runtime is inlined (`runtime/Alloc/Cells.cpp:313-322`).
- Array coordinates are unguarded, their extent bounding them
  (`Emit/Tensors.idr:59-66`); a `Fin` bound seeds `Ranges`
  (`IR/Ranges.cpp:158-161`); `natToFinLT` carries no range check
  (`Registry/Faster.idr:79-82, 101`).
- Doubles cross into bytecode by their bits (`MLIR/Bytecode.idr:693-696`).
- idr-narrow-lanes tests sizes at run time and binary-searches a bound in
  scratch copies (`Transforms/Narrow/Lanes.cpp:1-38`): the sizes are the
  program's input, and the coordinates' bound is relative to them, which no
  interval states. Essential.
- The Prelude's `div x y = case y == 0 of False => prim__div_Int x y`
  (`third_party/Idris2/libs/prelude/Prelude/Num.idr:128-130`) is followed
  by the primitive's `check.nonzero`: a second test of what the `Bool` match
  tested. No stage holds it as a fact (it is a `Bool` built of a
  comparison), so nothing is dropped; LLVM's dominating-condition folds
  likely remove the second test (conjecture).
- C285's table of decisions by op class is built once per pass instance
  (`EGraph/Rules.cpp:150-160`); its content is the build's, but the lookup
  pays only which registered op an operation is, as C285 states.

---

## Table

| # | Fact | Drop site | Rederive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|----------------|---------|---------------|-------|----------|
| 1 | a function's value intervals under final summaries | `Ranges.cpp:260-286` (solve destroyed after reading what it passes) | `Narrow.cpp:212` (versioning), `:91` (word rewrite), `:222-231` (whole analysis again after versioning) | the one solve, read once into `Facts`' `IndexVector<ValueId, Bounds>` at the arguments phase | ~50; 2 of 4 solves per function | L14, L12 | nothing |
| 2 | a natural's value fixed by a literal or by its instance's key | `Instances.idr:705-708` → `Types.idr:888` (`NatT IOpaque`); `Tensors.idr:175` reindex; `Refinement.cpp:113-123` (no constant fold) | none: computed at run time (`Bodies.idr:746` `nat.pred`, argument passed per call); `ranges::ofType` and e-graph leaf blind; `TypeLiterals.cpp:59-62` keeps two copies in step | `!idr.nat<k>` on the keyed parameter; reindex of a constant folds to it; literal built at its slot's type | few lines; run-time work in every keyed copy, one reindex per literal | L16, L04, L13, L14 | L16 C286 hunks, L04 `Refinement.cpp`; owner (core shape) |
| 3 | a big constant's integer and smallness | `Fold/Scope.cpp:50-72` (decimal print and parse each way) | every fold read (`Fold.h:220`, `Guards.h:66`), e-graph read and write-back (`EGraph/Values.cpp:561, 613`), fold result (`Fold/Values.cpp:103`), lowering per datum and per use (`StaticBytes.cpp:103-116, 133-140`) | the integer's words: small word or limbs, to and from `APInt` | ~30; print + parse + 2 allocations per crossing | L13, L21, L14, L11 | L14 D132 hunks |
| 4 | intervals of values and of functions' parameters and results | e-graph write-back (`Elaborate.cpp`), `Simplify.cpp:44-60` (constants only) | `Ranges.cpp:199-236` returns phase; `RuntimeCalls.cpp:40-56` per call; LLVM (no `range` on functions, `Lower/Functions.cpp:96-110`) | inherent parameter/result ranges on `idr.func`; LLVM `range` attributes | ~40; one solve per function | L14, L02, L21, L12 | L14 D132 hunks; owner (which op holds it) |
| 5 | a literal case's binding is its key; the default's none of the keys | `Bodies.idr:225-233` (`rebound`), `Monad.idr:104` (no literal refinement) | `LiteralMatch.cpp:61-69` + `IdentitiesRecord.cpp:74-85`; `Ranges.cpp:31-52, 89-118` + `IR/Ranges.cpp:46-75, 173-215` per solve; e-graph never (`Regions.cpp:21-28`) → run-time guard (`Checks.cpp:44-52`) | key constant as the case's binding (words); default's exclusions in the frontend's refinement, read by `specGuarded` | ~115; run-time guard tests | L16, L14, L13, L09 | L16 C286 hunks |
| 6 | a guard's verdict; a builder's guarantee | guard result typed as its operand (`Operations.idr:91-101`); refuted guard keeps its operand's interval (`OpsChecks.cpp:154-189`) | `guardsHold` per fold (`Traits.h:170-189`, `Fold.h:229-238`, `Numeric/Trait.h:74-81`, `EGraph/Values.cpp:248-257`); `getSpeculatability` per query (`Traits.h:191-212`); `GuardRepeated` (`Ops/Rules.cpp:94-101`); `neverEmpty` (`:30-52`); `NatPredOp::foldable` (`OpsBigs.cpp:228-233`) | absence of the guard + a refuted guard gives no value; a type parameter on our own types | ~75 | L03, L13, L14, L16 | L14, L16 hunks; owner (type refinement) |
| 7 | the range a type proves | e-graph `leaf` → empty facts (`Build.cpp:89,140,212`, `Nodes.cpp:272-275`); `ofType` drops a closed natural | `Ranges.cpp:60-72` seeds from `IR/Ranges.cpp:147-171`; e-graph's `guardRange` fallback (`Values.cpp:165-182`) | `ranges::ofType` asked by both engines at every entering value | ~10 | L14, L13 | L14 D132 hunks |
| 8 | the scalar-value bound of Integer→Char | Emit's own test (`Operations.idr:396-407`) | `int.to_char_s` decides it again (`Numeric/Inline.h:109-131`) | the one template, one op | ~10 | L16, L13 | L16 C286 hunks |
| 9 | the inner pipeline has no constants step (D132) | `Pipeline.idr:529-535, 566`; generated `IdrInnerPasses.td:33-36`, `Actions.h.inc:43-47` | — (a stale declaration; build break until regenerated) | the specification alone | ~10 | L03, INT, L06 | L14's D132 landing |
| 10 | a loop's natural only descends | not in the TTC, the call or the loop | `Versions.cpp:34-96` per loop | descent on the self call, kept by tail-loops | ~60 | L12, L16, L10, L17 | owner; conjecture |

## The three whose fix deletes the most

1. **Narrow's solve made three times (1).** Two of every four full dataflow
   solves per function (three of six when a loop is versioned) repeat the
   arguments phase's solve on the same IR under the same summaries; reading
   that solve once into the table `Facts` already builds deletes them. Read.
2. **A natural the compiler knows loses its value at every slot (2).** A
   copy keyed at a closed shape computes on its parameter at run time, and
   every natural literal passed to a call is hidden behind a reindex that
   folds no constant; the type the dialect already defines as "that
   natural" carries it, with one fold arm. Read; run-time cost unmeasured.
3. **Big constants through decimal text (3).** Every fold, e-graph read and
   write, and lowered use of a big prints it, parses it, and allocates; the
   `APInt`'s words are the runtime's small word or limbs directly. Read.
