<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation audit: sharing and ownership claims

Family: the grade's hold and claim (`static`, `counted`, `scoped`; nothing,
`unique self`, `unique deep`), freshness of a newly built value, the uses
that bound a claim, exclusivity's answers, reuse tokens; traced from
Emit's claims through the local rule, idr-in-place, idr-unique-results,
the specializer's keys and opening, bufferization's in-place decision,
counting's placement and reuse, the lowering and the runtime's count
tests.

- HEAD at start: `eedaf5d40a36a5423c2516364871ea901c2aaec7`
- HEAD at finish: `b2aab6e9ba40e43debc690277bf1eeda58adcfac` (L18aa landed
  during the audit: Open.cpp's regrade arms, `DataReindexOp::givenType`,
  Grades.h +18, Traits.h, Specialize.h; every line cited below was re-read
  at the finish).
- Read against the working tree, which carries the C286 cutover in
  progress (Emit, the grade spec, Local.h, Unique.cpp, Verify/Local.cpp,
  Verify/Program.cpp, OpsCon.cpp modified). "Modified now" below is
  `git status` at the finish.
- Grounds: read (the code says so), measured (counted by grep), conjecture
  (not built: nothing here needs no LLVM to run, so no compile was
  measured).

What already holds and is not a finding: counting's placement reads the
hold's release off the type (Placement.cpp:285-300); the lowering reads the
claim off the type for takes, drops, repacks and element boxes
(Lower/Counting.cpp:92, 116; Drops.cpp:374; Repack.cpp:264-270;
Elements.cpp:110); exclusivity follows only values whose grade leaves
their sharing open (Exclusivity.cpp:12-16, Facts.h:127-131); the runtime's
word kinds are template parameters the lowering picks from the type
(runtime/Rc/Rc.h:36-75), and its one `isCounted` comparison covers static
data and saturation at once, a run-time fact; re-inference after a grade
changes is one function (`families::takenTypes`, Substitute.cpp:456-470)
for idr-unique-results, idr-rc-exclusive and the specializer's regrade;
the local rule is one template (Local.h) its three readers instantiate.

---

## 1. Linearity re-read from use lists (the C282/C286 pattern's residue)

**The fact.** A value is used once on every path: the grade's `once`.

**First known.** Idris's checker for a quantity-1 binder, which Emit puts
in the grade (Emit/Bodies.idr:624-640, `MkWanted t (Just b) q`); under
C286, Emit also makes a fresh result at the uses its one consumer takes
(Emit/Operations.idr:441-453, Bodies.idr:142-146, Monad.idr:162-178
`consumedAt`). For every other value Emit sees the consumers when it emits
the body: a `let` its body uses once, a call's result consumed once.

**Dropped.**
- Emit/Operations.idr:237-247 `coerce`: a `many` value filling a
  quantity-1 position becomes the result of an `idr.lin.cast`; the value as
  made stays `many` and the once-ness lives on the cast alone. This is the
  C286 drop for every value C286 leaves `many`: a let at ω
  (Bodies.idr:624-640), every call result (finding 2).
- Emit/Bodies.idr:624-640: a `let` at ω is made `many` whatever its body
  does with it.

**Re-derived, per site, from use lists.**
1. `ownership::flowsLinearly` (include/idr/Analysis/Ownership/Local.h:295-300)
   = `once || value.hasOneUse()`, read at Transforms/InPlace/Unique.cpp:112,
   150, 196. Each site is conjoined with a once test
   (`uncountedClaims[usesOf] == Deep` at 113; `raisable`, which contains
   it, Unique.cpp:36-42, at 150 and 196), so the `hasOneUse` disjunct is
   dead in the working tree: a use-list read per value per solve, twice
   per compile (idr-in-place's `raiseClaims`, idr-unique-results), for
   nothing. (read)
2. idr-in-place, Chains.cpp:130-152 `usedOnce`, 111-128 `borrowedBefore`,
   41-58 `parameterOf`: for a `many` value, every other use is visited, its
   user's flow edges rebuilt (`readsPart`, Facts.h:295-314; `parameterOf`
   per use), and the IR's order climbed (`runsAfter`, Facts.h:278-290;
   `insideMutuallyExclusiveRegions`), per (value, strength) per requirement
   and again per transfer of every per-component fixpoint of the summaries
   (Rule.cpp:203-232). It also contradicts C286: a `many` value it admits is
   recorded (Versions.cpp:110-112) and graded by the writer
   (Writer.cpp:52-66, `claimed`, whose `leavesOpen`, Facts.h:127-131, never
   asks uses), which the working tree's stage rule refuses
   (Verify/Program.cpp:118-121, 181-183). tests/in-place-borrowed-read-ends
   (`let xs = build …`, read by `countW`, then taken by `bump`) is that
   case. (read; the failure is conjecture until run)
3. The specializer's keys: Specialize/Patterns.cpp:38-45 `shapeStep` and
   47-57 `constructorOf` (`throughLinear`, to see through the cast to the
   constructor), 133-147 `usedOnce` (`hasOneUse` along the shape);
   Specialize/Keys.cpp:124-128 (composeKey's check), 244-257 `sharedPart`
   and 263-282 `appliesBuiltClosures` (`throughLinear`, then `hasOneUse` on
   the cast and on the constructor): per argument per request, in every
   optimizer wave. (read)
4. Bufferize/Releases.cpp:220-237 `alone` (`linearPositions` and
   `hasOneUse`), finding 6. (read)
5. IR/Verify/Uses.cpp:36-54 `linearPositionOf`, `linearPositions`,
   `throughLinear` (a definition chain with cycle detection,
   Grades.h:295-327): the walk exists to go back through the cast to the
   value as made. 11 call sites outside Uses.cpp, 7 of them in this
   family, 4 in Narrow (bigs). (measured)
6. IR/Verify/Uses.cpp:126-149 `fieldReadOnce` (Grades.h:355-359), read by
   Families/Rules.cpp:31: walks a constructor's uses to count the reads of
   one index. It is reached only where the field's type equals the read's
   (Rules.cpp:29) with the field once, so the read is once and, by
   `times`, the constructor is once, whose uses the linearity verifier
   already bounds. (conjecture: redundant)

**The carrier.** The grade's uses on the value as made. Emit makes every
value at the uses its consumers take, extending C286 from "a fresh result
filling a quantity-1 position directly" to every value Emit sees consumed
once (a `let` used once on every path, a call's result consumed once, and
the results of finding 2), so no cast stands between a value and its one
consumer, and `once` is in the type, where Verify/Linearity.cpp holds every
pass to it. It fits the dialect as it is: the graded type's `uses`
parameter, the verifier already run after every pass, C286's own rule.
Two points are the owner's: an ω `let` made `once` raises a multiplicity
Idris left ω (sound under eager evaluation: its one consumer runs once);
and a `many` value used twice, one use a borrow (in-place-borrowed-read-ends),
stays `many`, so its in-place obligation is refused before counting or
carried by an explicit loan (finding 3).

**What the fix deletes.**
- Local.h:295-300 and the three conjuncts at Unique.cpp:112, 150, 196
  (certain, today).
- Chains.cpp:41-58, 111-152 and the `usedOnce` calls at 286-287, 326-327
  (a `many` value meets no requirement before counting, C286; a borrow is
  a loan, finding 3); Rule.h:207-216.
- Patterns.cpp: the cast branch of `shapeStep`, `throughLinear` in
  `constructorOf`, `usedOnce` (133-147) where the constructor is once.
- Keys.cpp: `hasOneUse`/`throughLinear` in `sharedPart` and
  `appliesBuiltClosures`, the check at 124-128.
- Releases.cpp:220-237 (with finding 6).
- Uses.cpp:36-54 and Grades.h:317-327 once Narrow's four uses go too
  (else they stay for bigs); Uses.cpp:126-149, Grades.h:355-359 and
  Rules.cpp:31.
- About 150 to 200 lines and every per-query use walk above.

**Owner, waits on.** L08 (Local.h, Unique.cpp, Chains.cpp, Rule.h,
Versions.cpp, Writer.cpp), L18 (Specialize/), L12 (Bufferize/), L05
(Uses.cpp, Grades.h), L04 (Families/Rules.cpp), L16 (Emit). Waits on the
C286 cutover (Local.h, Unique.cpp, Verify/Program.cpp, Emit's Bodies,
Operations and Monad modified now) and on an owner ruling on lets used
once. Confidence: read (1, 2, 5), conjecture (3, 6 redundant after the
extension).

---

## 2. A function's result is handed back once; its signature says `many`

**The fact.** A callee gives its caller one reference to its result, with
what the local rule proves of its returns (fresh, or one of its
parameters given back).

**First known.** In the callee: Unique.cpp's solve derives each result's
claim from its returning paths (Unique.cpp:321-357). Structurally, a call
has one consumer of each result, the call.

**Dropped.** compiler/src/IdrisMLIR/Emit/Index.idr:182-183,
`resultIn a t = grade Many (reachesIn a t) made …`: every function's,
closure's and suspension's result (Index.idr:159-162, 233-235;
Declarations.idr:94) is `many`, claiming nothing. Under C286's stage rule
(Verify/Program.cpp:214-220 for results, 181-183 for values, working
tree) a `many` value claims nothing before counting, so no result can
carry a claim to a caller before counting, and no pass makes a result
once before counting (no `Uses::Once` write in Transforms/ outside
Contracts, Counting, Tail and Lifetimes; measured).

**Re-derived, or dead.**
- idr-unique-results' interprocedural half is dead before counting:
  `raisable` (Unique.cpp:36-42) is false for every result Emit writes, so
  the result table and the per-component loop with its cyclic re-solve
  (Unique.cpp:321-357), `readCalled` (158-184), `Role::Called`, and
  `writeSignature` (UniqueResults.cpp:174-191) and `recall` (241-252)
  raise nothing; they run over the call graph's components every compile.
  (read)
- idr-in-place derives per result what it needs of its parameters:
  `summariesOf` (Rule.cpp:203-232, a fixpoint per component of
  `Chains::targets` per return operand per strength), `Why::ReturnShared`,
  Versions' results and demands; then the writer grades the result
  (Writer.cpp:69-73), a `many` result with a claim, which the stage rule
  refuses. tests/leet-relink-in-place reaches it: `length'` passes the
  list read out of `countRev`'s result to `rev`, which rebuilds it, so
  `countRev`'s result is demanded `unique self`. (read; the failure is
  conjecture until run)
- After counting, exclusivity follows "the result of a callee every return
  of which is" (Exclusivity.cpp:7-9) and keys versions by their results
  (Exclusive.cpp:57-72, 88-92).
- The cast after each call result filling a quantity-1 position (Emit's
  `coerce`) and every walk through it (finding 1).

**The carrier.** The result's grade in the function type at `once`: the
callee's one reference, handed over once. Its claim is the local rule's,
written once into the signature (`writeSignature`) and copied to every
call (`CallOp::copyCallee`); a caller that uses it many times casts it out,
forgetting the claim (`uncountedHold Many`). It fits the dialect as the
function type's results and upstream's `CallOpInterface`, and it is
C286's rule applied at the call boundary. The shape of a result's grade
is a core shape: the owner's.

**What the fix deletes.** With the carrier: the cast after every call
consumed once and the walks through it; in idr-in-place, the result
summaries a signature now states unconditionally (a fresh result) and the
writer's result grading as a second write of the same claim; the C286
contradiction. Without it: delete idr-unique-results' dead half (about
100 lines in Unique.cpp and UniqueResults.cpp), and idr-in-place must stop
grading results (Writer.cpp:47-49, 69-73; the results half of
`PromiseCopies`' key, GradeCopies.h:32-36), so every in-place obligation
through a call result can't be written before counting: it is either
refused or derived again after counting. Either way one of the two goes.

**Owner, waits on.** L16 (Index.idr), L08 (Unique.cpp, UniqueResults.cpp,
Rule.cpp, Versions.cpp, Writer.cpp, GradeCopies.h), L04
(Verify/Program.cpp). Waits on an owner ruling and on the C286 cutover
(Unique.cpp, Verify/Program.cpp modified now). Confidence: read; the test
failure is conjecture.

---

## 3. "A callee keeps nothing of this parameter": three markings

**The fact.** A use of a value by a callee that keeps nothing of it ends
with the call: a borrow.

**First known.** idr-in-place: `keepsOf` (Rule.cpp:157-197, a backward
marking of every parameter of the program from the uses that are not
hand-ons, along calls) and `Chains::borrowedBefore` (Chains.cpp:111-128).

**Dropped.** idr-in-place writes it nowhere: the borrowing use stays a
plain use of the value (no loan, no grade on the parameter), and `Keeps`
dies with the pass.

**Re-derived.**
- rcBorrows, Analysis/Ownership/Borrows.cpp:1-36, 109-123: a second
  backward marking of every parameter ("counted when the callee consumes
  any part of it … passed to a counted parameter"), and `usedAfter`
  (Borrows.cpp:102-107): per argument per call, every use, with
  `runsAfter`'s ancestor climb.
- Lifetimes/Lend.cpp lends each holder's reads on a stretch it finds
  again.
- Exclusivity's `copiedViews` (ExclusivityAnalyses.cpp:368-398) marks the
  parameters a reference is taken of through a view.
- Cost: two program-wide parameter markings, and per (use, call) the
  ancestor walk plus `isBeforeInBlock` of `runsAfter` (Facts.h:278-290) in
  Chains and Borrows, the per-query order walk AGENTS.md names (101edbc5).

**The carrier.** The parameter's convention as a fact of the function:
in-place's `Keeps`, written once per parameter on the function (as the
gives-back facts are kept, Analysis/Identities.h:78-111). No pass after it
adds a use of a parameter, so it stays true, and rcBorrows starts from it,
adding only what is its own (tail calls lend nothing, frames, quantity-1
arguments, the frame-limited rule). Or the borrow made an explicit loan
(`idr.lend`) where in-place proves it, so the consuming use is the value's
one use and finding 1's `usedOnce` sees one use. Which op or type holds it
is the owner's.

**What the fix deletes.** The part of Borrows' marking that repeats
`Keeps` (Borrows.cpp:109-123 and the consumption seeds of its body
reading); `Chains::borrowedBefore` and `parameterOf` (Chains.cpp:41-58,
111-128) with an explicit loan; `usedAfter`'s walk where liveness is
numbered once.

**Owner, waits on.** L08 (Rule.cpp, Chains.cpp, Analysis/Ownership/Borrows.cpp),
L07 (Counting/Borrows.cpp, modified now), L05 (Lend.cpp). Waits on a
design ruling. Confidence: conjecture (the two markings' rules differ in
tail calls, frames and quantity-1 arguments).

---

## 4. A fresh constructor's claim: computed two ways, dropped at Emit

**The fact.** A constructor's value is fresh; its claim is the
specification's `freshClaim` of its fields' claims (Grade.idr:432-434).

**First known.** Emit builds the constructor and holds every field's
hold. C282's Emit wrote `freshClaim given.parts` (HEAD,
Emit/Operations.idr).

**Dropped.** Working tree Emit/Operations.idr:441-453: the constructor is
written at `made` (Types.idr:518-519, counted, claiming nothing): "It
claims nothing: what a pass proves of it is the pass's to write."

**Re-derived.**
- `DataConOp::freshClaim` (IR/OpsCon.cpp:52-60) for every constructor the
  C++ builds (`DataConOp::build`, 64-70; Counting/CellInit.cpp:99 for
  `cell.init`).
- The local rule's Fresh and Built terms (Local.h:176-194, 247-259)
  compute the same claim from the flow edges: in Unique.cpp's solve
  (the `fresh` callback, 145-152, `Role::Raised`), twice per compile, and in
  `LocalCheck` after every pass. One function computed from types in one
  place and from edges in another, kept in step only by their agreeing.

**The carrier.** `idr.data.con` infers its result's claim
(`InferTypeOpInterface`, with a compatibility admitting a weaker claim as
`OwnAdoptOp::isCompatibleReturnTypes` admits one that only forgets,
Counting/Ops.cpp:189-192); the inference is `DataConOp::freshClaim`, the
specification's `freshClaim`, in one place. Every reader re-infers through
`families::takenTypes`, as reads and takes already do; Emit may print the
inferred claim or a weaker one.

**What the fix deletes.** The Fresh/Built path of the solve for
constructors (their results become `Role::Read`, re-inferred by the
writer); `LocalCheck`'s edge judgement of constructors (the op's verifier
holds them); C286's "claims nothing" in Emit. About 20 to 30 lines, and the
second derivation.

**Owner, waits on.** L04 (OpsCon.cpp, modified now; spec
Families/Ops.idr), L08 (Unique.cpp, Local.h, Verify/Local.cpp, modified
now), L16 (Emit, modified now), L03 (generated ODS). Waits on the C286
cutover. Confidence: read.

---

## 5. LocalCheck re-runs each op's inference to learn what its verifier decided

**The fact.** Which ops admit a result at a claim beyond their inference.

**First known.** Each op's declaration: only `cell.init` admits any grade
(CellInit.cpp:236-240) and `memo.take` any hold over its carrier
(OpsClosures.cpp:444-447); `own.adopt` only forgets (Counting/Ops.cpp:189-192);
the rest equal their inference.

**Dropped.** No trait says it; each op's compatibility answers per
instance.

**Re-derived.** IR/Verify/Local.cpp:137-149: for every op that touches a
claim, in every verification (after every pass), `inferReturnTypes` runs
again, though the op's own `verifyInvariants` ran it in the same
verification, to find which results exceed it.

**The carrier.** A trait from the specification on the ops whose
compatibility admits a claim beyond their inference (`cell.init`,
`memo.take`), which `LocalCheck` tests.

**What the fix deletes.** Local.cpp:137-149: one inference per op per
verification.

**Owner, waits on.** L08 (Verify/Local.cpp, modified now), L03 (spec
trait, generated td), L07 and L18 (the two ops' declarations). Waits on
C286. Confidence: read.

---

## 6. A linear array's buffer: its storage claim dropped at the field read, found again by walking back

**The fact.** A cell claiming `unique self` holds the only reference to
the storage of the buffer it holds (Grade.idr:212, `HeldBuffer`; 221-228,
`readUnique HeldBuffer Once Self = Self`).

**First known.** The cell's grade (idr-in-place's boundary grade, the
local rule).

**Dropped.** libs/mlir-array/Array/Core.idr:154-155 declares
`Writing : (elements : Array s a) -> LArray s a` at ω, so the field read is
`many` (`times`) and `readUnique _ Many _ = None` (Grade.idr:222): the
`HeldBuffer` row is never reached for this family. `to_tensor` then takes
the buffer at the bare grade, with an `idr.count.share` possibly between
(Releases.cpp:205-219).

**Re-derived.** Bufferize/Releases.cpp:220-237: per `to_tensor`, walk
`linearPositions` checking `hasOneUse`, look through one share and walk
again, match the `DataFieldOp`, read the cell's claim.

**The carrier.** The buffer's own grade from its read: the field at
quantity 1, so the read gives `unique self` by the specification's table
(but `freeze`'s `!*` needs ω: a library change, L20); or the one op that
opens a held buffer as a tensor reads its operand's claim, through a take
that moves the buffer out of the cell once. The owner's choice.

**What the fix deletes.** Releases.cpp:220-237, a user of
`linearPositions`/`throughLinear`.

**Owner, waits on.** L12 (Releases.cpp), L20 (libs), L05 (spec). Waits on
an owner ruling. Confidence: read.

---

## 7. The claims' order restated by enum ordinals

**The fact.** The order of claims, the lesser of two, a refinement.

**First known.** Spec/Grades/Grade.idr:84-128 (`Claims`, `claims`),
278-285 (`lesser`), 462-465 (`refine`), each proved.

**Dropped.** The generated header (Grades.h.inc) carries the holds'
tables, `freshestClaims` and `uncountedClaims`, but no table of `claims`,
`lesser` or `refine` on `Unique`.

**Re-derived.** Local.h:49-53 (`covers`, `lesser`, `greater` by
`static_cast<unsigned>`), Grades.h:115-117 (`Hold::claims` by ordinal),
133-137 (`Hold::refined`, a ternary ladder over the release), 154-165
(`weakest`, a loop over every hold per call), Facts.h:37-47 (`Asks`, a
second enum for `Unique` without `None`, and its conversions), OpsCon.cpp:52-60
(the fold of `freshClaim` written again). Correctness rests on
`Unique`'s declaration order matching `Claims`, with no `static_assert`.

**The carrier.** Generated tables from the specification's functions (the
order as a mask, `lesser`, `refine` per hold and claim, the meet of two
holds), and `Unique` where `std::optional<Asks>` stands.

**What the fix deletes.** About 25 lines of restatement; `Asks`,
`claimFor` and `asksFor`.

**Owner, waits on.** L05 (Grades.h; spec Grade.idr modified now), L08
(Local.h modified now, Facts.h), INT (Grades.h.inc, modified now). Waits
on C286. Confidence: read.

---

## 8. A reuse token's nullness tested again after the uniqueness test decided it

**The fact.** Where a take becomes `count.match_unique`, the unique region
holds the cell and the shared region holds none.

**First known.** The run-time test of the count (Lower/Counting.cpp:132-176):
a run-time fact, decided once.

**Dropped.** At the match's rejoin a token given on is merged with the
shared region's null token, its claim forgotten (Expand.cpp:20-27;
ReuseAssign.cpp:110-117, which keeps `unique deep` only where every path
does).

**Re-derived.** At run time, `freeMaybeToken` or the recycle's null test
(Lower/Counting.cpp:179-188) tests the same fact again.

**The carrier.** Control flow: a cell on both paths, as `take_into`
already gives ("the code after the match has a cell either way and tests
nothing"), or the token's consumer sunk into each region. The cost is an
allocation on the shared path where the consumer is a free, so the test is
essential there.

**What the fix deletes.** `freeMaybeToken` and the maybe-null recycle
where the consumer is a recycle.

**Owner, waits on.** L07 (Expand.cpp, ReuseAssign.cpp), L21
(Lower/Counting.cpp), L11 (runtime helper). Confidence: conjecture (cost
not measured).

---

## 9. An op's declared moves enumerated again by every reader

**The fact.** An op's flow edges, a function of its kind and its types.

**First known.** Its `FlowOpInterface` (FlowOps.cpp, Counting/Flow.cpp …).

**Dropped.** Built into a fresh `FlowEdges` on each call and thrown away.

**Re-derived.** 81 `getFlowEdges`/`flowEdgesOf` call sites (measured); in
this family per query: `readsPart` per use (Facts.h:295-314, from
`Chains::usedOnce` per other use and `handsOn` per use in `keepsOf`),
`parameterOf` per use (Chains.cpp:43-58), `ownerOfPart` per value
(Uses.cpp:236-283), `readOutOfElements` per value (Facts.h:319-345),
`takesRaised` per use of a raised value (UniqueResults.cpp:99-145),
`LocalCheck` per op per verification (Local.cpp:126-127), Open.cpp's
regrade. Also `crossedAs` climbs from an edge to its program's stage per
comparison of two differing holds (Grades.cpp:227-240).

**The carrier.** A per-body edge table numbered once by the solver's walk,
kept in the analysis manager for every pass that does not change the body
(as `ProgramGraph` is), each reader indexing it.

**What the fix deletes.** The per-query builds and the readers' own
enumerations.

**Owner, waits on.** L09 (Flow.h, FlowEdges, FlowOps.cpp, modified now),
L08, L05. Confidence: conjecture (cost not measured).

---

## 10. The boundary obligation: a fact of a parameter's type, computed by a pass

**The fact.** A quantity-1 parameter of an `in_place` family whose own
cells hold a buffer is owed `unique self` by every caller.

**First known.** The parameter's type: its uses and its family's
declaration (promise, own buffers).

**Dropped.** Emit writes every parameter at `made`, claiming nothing
(Index.idr:160; Types.idr:518-519).

**Re-derived.** idr-in-place's `boundaryAsks` (Rule.cpp:132-138), from the
type alone, every compile, then written as the parameter's grade.

**The carrier.** The type: Emit writes the parameter's claim by the
specification's rule (generated to both sides), or the graded type's
canonical form gives it.

**What the fix deletes.** `boundaryAsks` and the obligations it seeds in
idr-in-place.

**Owner, waits on.** L08 (Rule.cpp), L16 (Emit), L05 (spec). Confidence:
read.

---

## All findings

| # | Fact | Drop site | Rederive sites | Carrier | Lines deleted (est.) | Owner | Waits on |
|---|------|-----------|----------------|---------|---------------------|-------|----------|
| 1 | a value used once | Emit `coerce` (Operations.idr:237-247), `let` at ω (Bodies.idr:624-640) | Local.h:295-300 (dead); Chains.cpp:41-58, 111-152; Patterns.cpp:38-57, 133-147; Keys.cpp:124-128, 244-282; Releases.cpp:220-237; Uses.cpp:36-54, 126-149 | the grade's uses on the value as made (C286 extended to every single-consumer value) | 150-200 | L08, L18, L12, L05, L04, L16 | C286 cutover; owner on lets used once |
| 2 | a result handed back once, with its claim | Index.idr:182-183 (`resultIn` = many) | Unique.cpp:158-184, 321-357 and UniqueResults.cpp:174-191, 241-252 (dead); Rule.cpp:203-232 summaries; Writer.cpp:69-73 (contradicts the stage rule); Exclusive.cpp:57-92 | result grade `once` in the function type, claim written once by `writeSignature` | ~100 either way | L16, L08, L04 | owner ruling (core shape); C286 |
| 3 | a callee keeps nothing of a parameter | in-place writes no loan or grade; `Keeps` dies with the pass | Analysis/Ownership/Borrows.cpp:102-123; Lend.cpp; ExclusivityAnalyses.cpp:368-398; `runsAfter` per query | per-parameter fact on the function, or an explicit `idr.lend` | 40-80 | L08, L07, L05 | design ruling |
| 4 | a constructor's fresh claim | Emit `con` writes `made` (Operations.idr:441-453) | OpsCon.cpp:52-60 vs Local.h:176-194, 247-259 (Unique.cpp:145-152, LocalCheck) | `idr.data.con`'s inference (`freshClaim`) | 20-30 | L04, L08, L16, L03 | C286 |
| 5 | which ops admit a claim beyond inference | no trait | Verify/Local.cpp:137-149 per op per verify | spec trait on `cell.init`, `memo.take` | ~13 | L08, L03 | C286 |
| 6 | a cell's claim covers its buffer's storage | ω field (libs Core.idr:154-155) and `readUnique _ Many` | Releases.cpp:220-237 | the buffer's grade from its read, or an opening op reading its operand's claim | ~20 | L12, L20, L05 | owner ruling |
| 7 | the claims' order, lesser, refine | no generated table | Local.h:49-53; Grades.h:115-117, 133-137, 154-165; Facts.h:37-47; OpsCon.cpp:52-60 | generated tables; `Unique` for `Asks` | ~25 | L05, L08, INT | C286 |
| 8 | a token holds a cell on the unique path | rejoin merges with the null token (ReuseAssign.cpp:110-117) | Lower/Counting.cpp:179-188 at run time | a cell on both paths, or the consumer sunk | ~10 + a run-time test | L07, L21, L11 | none |
| 9 | an op's flow edges | rebuilt per call | Facts.h:295-345; Chains.cpp:43-58; Uses.cpp:236-283; UniqueResults.cpp:99-145; Local.cpp:126-127; Grades.cpp:227-240 | per-body edge table in the analysis manager | ~0 deleted, per-query work removed | L09, L08, L05 | Flow.h cutover |
| 10 | the boundary obligation | Emit writes parameters at `made` (Index.idr:160) | Rule.cpp:132-138 | the parameter's type by the spec's rule | ~15 | L08, L16, L05 | none |

The three whose fix deletes the most: 1 (every per-site reading of a
value's uses, across idr-in-place, the specializer, bufferization and the
e-graph), 2 (the interprocedural result derivation, today dead before
counting while idr-in-place writes what the stage rule refuses), 3 (the
second program-wide marking of what a callee keeps).
