# Rederivation audit: multiplicities and uses

Family: Idris's quantities (0, 1, ω) on binders, arguments, fields and
results; their path through the checker and its TTC, the frontend's
boundary and translation, Emit's grades (`once` or `many`), the
specification's tables, the passes that read or change uses (casts into
and out of linear positions, counting, the in-place promise,
idr-unique-results, the specializer), the lowering and the runtime.
Erasure (quantity 0 is no value of the module) is included.

- HEAD at start: `eedaf5d40a36a5423c2516364871ea901c2aaec7`
- HEAD at finish: `b2aab6e9ba40e43debc690277bf1eeda58adcfac` (8b2cd180,
  L18aa's reindex typing, and b2aab6e9, a queue entry, landed during the
  audit; neither touches a site below)
- Ground: everything here is **read** from source. Nothing was measured:
  this machine has no built C++ tool (LLVM builds go to the other
  machine), and I did not build the frontend. Where a cost is given it is
  the shape of the work (per op, per query, per run), not a number.
- In flight: C286 is being carried out uncommitted in the checkout (Emit's
  `con` takes the consumer's uses, `coerce` writes `uncountedHold`,
  `givenClaim`/`Constituent` go from `Spec/Grades/Grade.idr`,
  `Declarations.idr` and `Analysis/Ownership/Local.h`, `raisable` now
  requires `once`). That earlier drop-and-rederive pair is closed by the
  in-flight change and is not counted here. The findings below are read
  against the checkout as it now stands, in-flight edits included, and
  each one says whether its files are modified now.

Where each fact is first known, for every finding below:

- Quantity on a binder: the checker's `RigCount` on each `Pi`, `Lam` and
  `Let` of checked TT, read at the boundary by
  `compiler/src/IdrisMLIR/Frontend/Resolve.idr:205-209` (`use`), into
  `Types.Binder.quantity : Uses` (`compiler/src/IdrisMLIR/Types.idr:167-170`).
  `Uses` is the specification's (`compiler/spec/IdrisMLIR/Spec/Grades/Grade.idr:27`),
  and the C++ enum is generated from it, so there is one source.
- Erasure of a definition's position: the checker's `eraseArgs`
  (`compiler/checker/src/TTImp/ProcessType.idr:179-185`,
  `TTImp/Elab/Utils.idr:39-74`, kept by the TTC at
  `Core/TTC.idr:1446`).
- The uses a consumer takes a value at: Emit's `Wanted.uses`
  (`compiler/src/IdrisMLIR/Emit/Monad.idr:157-178`), taken from the
  slot's binder (`Emit/Bodies.idr:141-146`).

The pattern every finding has: a fact Idris or Emit holds is written at a
weaker type (a `many` grade, a bare carrier, a missing verifier rule), and
a later stage recovers it from use lists, by walking through casts, by a
whole-program solve, or at run time.

---

## R1. Function results and region results are emitted at `many`: the consumer's uses and the fresh value's claim are dropped at every return and yield

**The fact.** A value a function returns, or a match, join point or array
region yields, is fresh to its consumer. Emit knows the uses that consumer
takes it at (`w.uses`), and since C286 it builds a constructor at those
uses. C286 records the intent: "Claims before counting live on values used
once and fresh results used once" (`proposals/0000-mlir-native.md:2793`).

**First known.** `Emit/Monad.idr:162-172` (`Wanted.uses`), passed into
every arm (`Emit/Bodies.idr:679`, `:692`, `:717`, `:720`, `:737`, `:739`)
and into `con` (`Emit/Bodies.idr:617-620`).

**Dropped.**
- Every function result is graded `many` whatever its body returns:
  `Emit/Index.idr:179-183` (`resultIn a t = grade Many ...`), for
  definitions, closures' `FnType` results and suspensions alike.
- A function's tail is built at `many`: `returning`
  (`Emit/Bodies.idr:190-193`) passes `expecting` (`Monad.idr:176-178`,
  `consumedAt t Many`), so a fresh constructor in tail position is born
  `many` and claims nothing (the in-flight C286 rule).
- Every region's value is cast out to `many`: `plain`
  (`Emit/Bodies.idr:180-183`, `coerce ix l Many`) at each match arm
  (`:679`, `:692`), each literal-match arm (`:717`, `:720`), each
  natural-match arm (`:737`, `:739`), a join point's body (`:539`) and the
  array regions (`:821`, `:828`, `:847`, `:868`, `:888`). An arm that
  built a `once` value for a linear consumer Leave-casts it
  (`Emit/Operations.idr:237-247`), and the in-flight `uncountedHold Many`
  sets its claim to none. After the match, the consumer's `coerce` casts
  the region's result back in (Enter), still claiming none.
- A call's result is `many` (`Emit/Bodies.idr:612-614` through
  `Tensors.idr:220-223` and `Operations.idr:196-199`), then cast in where
  its consumer is linear.

**Re-derived.**
- `idr-unique-results` (the in-place promise's pass, named for the
  results it raises): the in-flight `raisable` requires `once`
  (`foreign/idr/lib/Transforms/InPlace/Unique.cpp:35-42`), and no
  function result is ever `once`, so the result half of the solve now
  derives nothing. Every result's entry is `claimOf(type)`
  (`Unique.cpp:327-330`); the re-solve loop for raised results
  (`Unique.cpp:333-350`) never sees a raisable result; `readCalled` and
  `Role::Called` (`Unique.cpp:158-187`, `:290-291`) read only those
  entries; and `writeSignature`, `resultsChanged` and `recall`
  (`InPlace/UniqueResults.cpp:174-190`, `:241-253`, `:327`) never change
  anything. Before C286 this machinery recovered the result's claim by a
  program-wide callees-first solve. After C286 it cannot recover it at
  all.
- `idr-rc-exclusive` (`Transforms/Ownership/Exclusive.cpp:3-21`, with
  `Analysis/Ownership/Exclusivity*.cpp`) says that "what QTT and
  freshness prove is in the types already (idr-unique-results), so the
  solve follows only the rest". With results and yields at `many`, that
  premise fails, so after counting the program-wide context-sensitive
  solve has to re-derive each fresh result's claim, and each claim it
  proves for some callers but not others costs a grade copy of the
  function. Cost: per run, program-wide, plus code size for each copy.
- At run time: where the solve fails, a take or a reuse of the value
  expands to `count.match_unique`, which lowers to a call of
  `idris_rt_is_unique` and two regions
  (`Conversion/Lower/Counting.cpp:134-171`). That is a test on every
  execution of each such site, for a fact Emit had (**conjecture** on how
  often the solve fails; the code path is read).
- Contracts: linear-kept compares results' uses
  (`Transforms/Contracts/Contracts.cpp:245-275`, `:326-352`, with
  `tests/contracts-linear-kept`) for a state Emit never writes. Only the
  hand-written test module has a `once` result.

**The carrier.** The result types of the boundary ops, at the uses their
consumer takes. MLIR already gives these a home: `idr.func`/`idr.call`
result types, which CallOpInterface keeps equal, and region branch
results (RegionBranchOpInterface), which `crossedAs`
(`include/idr/IR/Grades.h:237-247`) already lets differ in hold at edges.
This is an architectural choice (which type holds the fact), so it goes
to the owner with two options:

- (a) Grade a function's result `once`, carrying its claim: the return is
  the result's one use. A caller that uses it many times casts it out, as
  it does for any linear value. Each region result takes the uses Emit
  already passes into its arms (`w.uses`) in place of `plain`'s `Many`.
  Benefits: C286's "fresh results used once" holds for calls and matches
  as well as constructors; idr-unique-results' result solve does what its
  name says, before counting; rc-exclusive follows only what freshness
  cannot prove; the run-time tests above go wherever freshness is the
  proof. Costs: `Optimize/Results.cpp:204` refuses to drop a linear
  result (its reason, "Idris checked that one used once is used", is
  about parameters), so dead-result elimination would need its own rule
  for results. The specializer's result regrading
  (`Specialize/Open.cpp:715`, `:764`) and linear-kept change meaning.
  Every call or match result a caller uses many times gains a cast.
- (b) Keep results at `many` and delete what that leaves dead: the result
  half of idr-unique-results (about 100 lines over `Unique.cpp`,
  `UniqueResults.cpp` and `Unique.h`'s `Called` role and `Results`
  table), linear-kept's result half and its breaker (about 30 lines with
  the test). Fresh results' claims then come from rc-exclusive alone,
  and from the run-time test where it fails.

**What the fix deletes.** Under (a): the Leave/Enter pair at every match
in a linear position (`Bodies.idr:183`'s `coerce Many` becomes the
consumer's uses); rc-exclusive's work re-deriving fresh results, and the
grade copies it makes for them; the run-time uniqueness tests freshness
would have proved. Under (b): about 130 lines of solve and contract code
that the in-flight C286 has already made dead.

**Owner and status.** Emit is L16 (`compiler/src/`).
`Emit/Bodies.idr`, `Monad.idr` and `Operations.idr` are **modified in the
checkout now** (C286 in flight). `InPlace/` is L08 (`Unique.cpp`
**modified now**), `Ownership/` L08, `Contracts/` L19, `Optimize/` and
`Specialize/` L18, `Conversion/Lower/` L21. Waits on C286 landing, then
the owner's choice between (a) and (b). **Confidence:** read. That the
result solve is dead follows from `raisable` (in flight) and
`Index.idr:183` (committed). The run-time cost is conjecture.

---

## R2. A constructor's fields are built at their declared quantity, not at the product with the value's uses; data.con lacks the product rule closures carry

**The fact.** QTT's product: a field of a value used `u` times is used `u
* q` times. The specification proves it (`Spec/Grades/Grade.idr:30-35`,
`times`). The closures' ops carry it as a trait ("a closure over a linear
capture is linear": `ResultUsesMaxOf`, `Spec/Core/Op.idr:218-222`,
`Spec/Closures/Declarations.idr:304`, checked by
`include/idr/IR/Traits.h:134-150`).

**First known.** The constructor's declared field quantities
(`Types.Binder.quantity`) and Emit's `w.uses` for the value
(`Emit/Bodies.idr:617-620`).

**Dropped.**
- Emit builds each field in a slot of its declared quantity, not
  `times u q`: `fields` (`Emit/Bodies.idr:176-178`, through `operand1`'s
  `uses = maybe Many (.quantity) slot`, `:143`), and `fieldOperands`
  casts each to `b.quantity` (`Emit/Operations.idr:437`). A `many` value
  of a family with a quantity-1 field gets a `once` operand.
- `data.con`'s verifier admits that state: `fillsField`
  (`IR/Counting/Ops.cpp:53-62`, `:57`) only checks that a `once` operand
  fills a `once` field, never that the value it builds is `once`, and
  `DataConOp` has no `ResultUsesMaxOf` (`IR/OpsCon.cpp:107-131`).
  Defunctionalization turns each closure into a `data.con`
  (`Defunctionalize/Convert.cpp:291` keeps its uses), and from then on no
  rule ties the value's uses to its fields'.

**Re-derived.**
- `fieldReadOnce` (`IR/Verify/Uses.cpp:125-150`, declared
  `include/idr/IR/Grades.h:355-359`) walks the tree of the value's
  uses through every cast to count reads of one field. It runs on each
  `FieldOfCon` decision and each `DataFieldOp::fold` of a field read off
  a constructor (`IR/Families/Rules.cpp:24-33`, `:75`, `:84`;
  `IR/OpsConReads.cpp:97`): a per-query walk. Its tree case exists for
  the dropped state: a `many` value Enter-cast into two linear positions,
  each reading the `once` field.
- `LazyForceOp::fold` tests `hasOneUse` on a delay of a linear value
  (`IR/OpsClosures.cpp:263`), though `ResultUsesMax` already makes such a
  delay `once`.
- The specializer's `usedOnce` (`Transforms/Specialize/Patterns.cpp:135-147`,
  used at `Keys.cpp:126-128`) walks each constructor of a shape that holds
  a linear leaf checking `hasOneUse`. Part of that check is essential
  (the shape must die with the call, since the constructor dominates the
  call's other paths), so only its Enter-cast arm goes.

**The carrier.** A verified property of `data.con`: an operand that fills
a field is at `times(result uses, declared quantity)` or more (a `many`
operand still fills a `once` field). It is generated as the closures'
`ResultUsesMaxOf` is, from the specification's `times`, and Emit builds
fields at `times w.uses q`. Then a `once` field read implies a `once`
constructor read directly, and `FieldOfCon` asks one `hasOneUse` of the
constructor's result (for the dominance reason) in place of a tree walk.

**What the fix deletes.** `fieldReadOnce` and its declaration (about 27
lines), replaced by one `hasOneUse`. `LazyForceOp::fold`'s use test (1
line). The Enter-cast case of `usedOnce`. The state itself, which no
verifier refused.

**Owner and status.** `OpsCon.cpp` is L04 (**modified now**), with
`Families/Rules.cpp` and `OpsConReads.cpp` (**modified now**).
`Counting/Ops.cpp` is L07. `Verify/Uses.cpp` and `Grades.h` are L05.
`OpsClosures.cpp` and `Specialize/` are L18. Emit is L16 (**modified
now**). The trait's declaration in `Spec/Families` is L04's. Waits on
C286. **Confidence:** read. The soundness argument (a `once` read of a
`once` field implies the constructor is read directly) assumes the
e-graph equates no cast pair whose inner cast has another use; check
that against `LinCastOp::fold` (`IR/Lifetimes/Cast.cpp:62-70`).

---

## R3. A field's buffer is cast to the bare carrier before `to_tensor`, so bufferization re-walks casts and use lists to recover its uses and claim

**The fact.** A buffer read out of a cell is used once (by the one
restricted `to_tensor` Emit builds of it) and holds what the cell's claim
gives it.

**First known.** `Emit/Bodies.idr:396-421` (`caseFields`): the field read
is typed at the field's uses `q` and `fieldHold` (`readHold reach q
r.hold`), and its one consumer is the `to_tensor` built on the next line.

**Dropped.** `Emit/Bodies.idr:416-420`: the buffer is cast to the bare
carrier (`Idr.linCastOp buf []` at `Once`, or used bare at `Many`), which
forgets its uses and its claim, because upstream's `to_tensor` takes the
bare type. Counting may then put a `count.share` between the two
(forgetting the claim again).

**Re-derived.** `Transforms/Bufferize/Releases.cpp:207-237`: for every
restricted `to_tensor`, `alone` walks `linearPositions` checking
`hasOneUse` at each step (`:222-224`), `throughLinear` back to the read
(`:228`), the same again through a share (`:229-233`), and then reads the
scrutinee's claim again (`:235`) to set `writable`. Cost: per run, a walk
per `to_tensor`. The walk is also what keeps the cast helpers
`linearPositions` and `throughLinear` alive (see R10).

**The carrier.** The field read's grade, which every pass that raises a
claim already re-infers (`InPlace/UniqueResults.cpp:276-278`, `:296-303`,
`Ownership/Exclusive.cpp`'s inference again). The writable fact can be
written where the claim is written. Or an op of ours that reads a buffer
field as a tensor, taking the cell, so the claim is its operand's type
and no chain stands between them. Choosing between those is an
architectural question for the owner.

**What the fix deletes.** `alone` and the chain walk in `prepare` (about
30 lines). The `lin.cast` to the bare carrier in `caseFields` (5 lines).

**Owner and status.** `Bufferize/` is L12 (`Bufferize/Reindex.cpp`
**modified now**; `Releases.cpp` not). Emit is L16 (**modified now**).
**Confidence:** read.

---

## R4. `flowsLinearly` re-derives "used once" from the use list, and every caller already requires `once`

**The fact.** A value graded `once`.

**First known / carried.** Its type (`usesOf`).

**Re-derived.** `include/idr/Analysis/Ownership/Local.h:295-300`:
`usesOf(...) == Once || value.hasOneUse()`. The use-count arm stood in
for values Emit built at `many` and cast in (the pre-C286 state). Every
caller now also requires `once`: `Unique.cpp:112` (with
`uncountedClaims[usesOf(...)] == Deep` beside it), `:150` and `:196`
(behind `raisable`, which in flight requires `once`, `:35-42`). So the
predicate is never the deciding conjunct, and its `hasOneUse` arm is
dead.

**The carrier.** The grade's uses, which `raisable` and `uncountedClaims`
already read. While touching this, spell `uncountedClaims[...] ==
Unique::Deep` at `Unique.cpp:41` and `:113` as the stage rule it is,
rather than as a disguised test for `once`.

**What the fix deletes.** `flowsLinearly` (6 lines) and its three
conjuncts.

**Owner and status.** L08. `Local.h` and `Unique.cpp` are **modified
now** (C286 in flight), so this folds into that change. **Confidence:**
read.

---

## R5. A closure's linearity is computed by hand in Emit from the printed MLIR types of its captures, though the specification declares the rule

**The fact.** A closure or suspension is `once` exactly when a capture
is: `ResultUsesMaxOf` (`Spec/Core/Op.idr:218-222`), whose comment says
it is "printed to the C++ check and to the frontend's builder, which
computes the result's grade from it".

**Dropped.** Nothing prints it to the frontend: only the ODS generator
reads the trait (`Spec/Generator/Ods.idr:318-319`, `:951`), and the
generated `fnClosureOp` takes a result type
(`compiler/src/IdrisMLIR/Dialect/Idr.idr:1015`). Emit passes each capture
as a bare `Value` (`Emit/Bodies.idr:773-775`, `:799-801`: the `captures` `lift` returns), losing `Val.uses`.

**Re-derived.** `holding` (`Emit/Bodies.idr:452-467`) pattern-matches
each capture's emitted MLIR type for `Idr (GradedType Once _ _)` to
recompute the rule. It is a second copy of the trait, read off Emit's own
output, and the C++ verifier holds the two in step.

**The carrier.** The specification's trait, generated into the Idris
builder so that it computes the result's grade from its captures' `Val`s
(as the comment already claims it does), or Emit's `Val.uses`, never the
printed type.

**What the fix deletes.** `holding`'s `linearType` and its branch (about
16 lines). Together with R2, the closure and data copies of the product
rule become one generated rule.

**Owner and status.** Emit is L16 (`Bodies.idr` **modified now**). The
generator and `Op.idr` are L03. The closures' spec is L18. **Confidence:**
read.

---

## R6. Literal and natural matches cast a `once` scrutinee out to `many`

**The fact.** A string, big integer or natural bound at quantity 1, and
matched.

**First known.** The scrutinee's `Val.uses` (`Emit/Bodies.idr:714`,
`:733`, `:735`, `standing (sc.vars x)`).

**Dropped.** `coerce ix l Many` before `idr.lit.match` at those three
lines. The arms then rebind the scrutinee at `many`, and the in-flight
`uncountedHold Many` gives it no claim. `idr.lit.match` takes a
scrutinee "at any grade" (`Spec/Control/Matches.idr:63-65`, `:250`), and
the data match takes its scrutinee as held (`Bodies.idr:642-660`). The
problem has no second case here: the cast is accidental.

**Re-derived.** Whatever the arms do in place with the value (a string
append, a natural's predecessor) needs rc-exclusive to prove what the
quantity gave, or the run-time test of R1 (**conjecture**: I did not
trace which runtime string or big operations take a claim).

**The carrier.** The scrutinee's own grade, as the data match keeps it.

**What the fix deletes.** Three casts per such match, and the
re-derivation they force.

**Owner and status.** L16 (`Bodies.idr` **modified now**). **Confidence:**
read for the drop, conjecture for the cost.

---

## R7. Erasure is decided twice in the frontend: from `eraseArgs` and from the binder's quantity, and in two walks of one term

**The fact.** A position Idris erased.

**First known.** The checker's `eraseArgs`, which `findErasedFrom` computes
from the quantity-0 binders of the type in normal form
(`TTImp/Elab/Utils.idr:39-74`; for case blocks,
`TTImp/Elab/Case.idr:404-406`, `:418`).

**Read twice.**
- `argumentAt` (`Frontend/Translate/Closed.idr:410-424`) reads
  `erasedPosition` (`eraseArgs`), and if that is false it reads the same
  binder's `RigCount` (`byQuantity`), which in normal form is the same
  fact. `TypeConstructors.idr:121`, `Types.idr:105`, `:1072`,
  `Boundary.idr:1216` and `Growth/Sites.idr:773`, `:2139` call it.
- The growth model's walk and the translation each decide `Erased` versus
  `Used` at the same binders (`Growth/Sites.idr:1769-1804`, `:1869`,
  `:2051`; `Translate/Terms.idr:713-722`, `:798-808`, `:909-915`). C281
  already says the translation should fold the decided tree rather than
  decide again.

**Re-derived cost.** Per binder, a cheap `elimSemi`. The cost is not the
work but the two sources that must agree (case blocks normalise with a
depth limit, `Case.idr:404`, which the frontend's own normal form does
not share: **conjecture** that the two can differ there).

**The carrier.** One reading: the binder's `ArgumentAt` on C281's
annotated tree, read once from `eraseArgs` (the checker's decision, kept
by the TTC), with `byQuantity` only for types no definition has
(`argumentsIn`, `Closed.idr:430-435`).

**What the fix deletes.** `erasedPosition`'s second source (about 6
lines), and the translation's own `case use rig` at the binders C281's
tree decides.

**Owner and status.** L16 (`Closed.idr`, `Terms.idr`, `Sites.idr`,
`Types.idr`, `TypeConstructors.idr`, `Boundary.idr` all **modified
now**). Waits on C281's fold (L16eo). **Confidence:** read; the
case-block difference is conjecture.

---

## R8. The proved uses the quantities-kept contract compares are keyed by an identity in a discardable location

**The fact.** The uses Idris proved of each parameter.

**Carried.** The parameter's type, and a `#idr.binder` identity Emit
fuses into the block argument's location (`Transforms/Expect/Quantities.cpp:1-15`).

**Dropped.** A location is discardable: a pass may drop or replace it,
and `identityOf` (`Quantities.cpp:28-40`) then finds nothing and
`usesKept` skips the binder silently (`:79-95`). AGENTS.md says not to
keep a fact where it can be dropped silently.

**Re-derived.** After every pass, under `--idr-contracts` (in tests
only, `include/idr/Transforms/Contracts.h:17-19`), each block argument's
location is walked and its uses compared with a `DenseMap<BinderAttr,
Uses>` snapshot (`include/idr/Transforms/Expect.h:401-412`).
linear-kept compares the same parameters again, by symbol
(`Contracts.cpp:274`). quantities-kept also follows a parameter carried
into a region (inlining, contification), which linear-kept cannot, so
the two are not one fact checked twice.

**The carrier.** Not settled here. A check that cannot lose its
identity would key on something a pass cannot silently drop. This is a
test oracle, so the case is the owner's.

**What the fix deletes.** Nothing at compile time. It removes a check
that can quietly check nothing.

**Owner and status.** L19 (not modified now). **Confidence:** read.

---

## R9. The registry's `Multiplicity` restates the frontend's `Use`

`Registry/Entry.idr:113` (`M0 | M1 | Mw`) and `Frontend/Resolve.idr:205`
(`Erased | Used Uses`) are one fact. `multiplicity`
(`Resolve.idr:211-215`) converts one to the other at every `Pi` that
`shapeOf` reads (`:240`), and `Profile.idr:328` reads it back with
`isErased`. Nothing is re-derived at a cost, but a second enum of one
fact drifts. Carrier: the registry's shapes over `Use`. Deletes the enum,
its `Eq` and its printer (about 12 lines) and the conversion. L16
(`Registry/Libraries.idr` **modified now**; `Entry.idr` not).
**Confidence:** read.

---

## R10. Two walkers of "the same value through its grade changes"

`linearPositions`/`throughLinear` (`IR/Verify/Uses.cpp:35-54`) follow
`SameValue` ops whose uses differ. `sourceOf` (`:61-70`) already answers
`Same` for every `SameValue` op, and `arrayRoot` and `viewRoot` walk that
chain. The cast-only walker exists because casts at boundaries (R1) and
into fields (R2) stand between a value and the op that made it. Its
readers are the specializer (`Specialize/Patterns.cpp:44`, `:50`;
`Keys.cpp:250`, `:273`), narrowing (`Narrow/Carried.cpp:68`,
`Versions.cpp:64`, `Narrow.cpp:152`, `Facts.cpp:125`) and R3's
bufferization walk. After R1 and R2 the casts that remain are the
essential Enter casts of genuinely `many` values. The walker that remains
should be one `definitionChain` over `sourceOf`, restricted where a
reader needs it. Deletes about 10 lines once R1 to R3 land. L05
(`Verify/Uses.cpp`), readers L18 and L12. **Confidence:** read.

---

## Checked and not a finding

- The linearity verifier (`IR/Verify/Linearity.cpp`) checks the grade's
  uses against the IR after every pass. That is the carrier being
  verified, not a re-derivation.
- `Uses` is the specification's in both hosts (`Types.idr:20` imports
  `Spec.Grades.Grade`; the C++ enum is ODS-generated from it). There is
  no hand copy.
- Erased positions emit no value: `NoValue` stops at the translation.
  No C++ pass re-derives erasure (`BindingTimes.cpp` finds parameters
  passed unchanged, which is a different fact).
- Counting (`Counting/Placement*.cpp`, `Expand.cpp`, `ReuseAssign.cpp`),
  `Optimize/Demand.cpp:89`, `Captures.cpp:188` and `Results.cpp:204` read
  the grade from the type. Use-list reads in Joins, Tail, Lend and
  Optimize are dead-code tests, not linearity.
- The translation's `OfValue Many` lets (`Translate/Cases.idr:673`,
  `:1001`; `Terms.idr:1132`, `:2056`; `Programs.idr:195`) bind forced,
  held or computed values that are shared by meaning (a memo's value, a
  dictionary field), so `many` is right there. `Terms.idr:230` binds an
  argument at its parameter's quantity.

---

## Table

| # | Fact | Drop site | Rederive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|----------------|---------|---------------|-------|----------|
| R1 | A fresh result's uses at its consumer, and its claim | `Emit/Index.idr:183` (results at `many`); `Emit/Bodies.idr:183` (`plain`), `:190-193` (tail at `expecting` = Many), arms `:679,692,717,720,737,739`, join `:539`; call results `Operations.idr:196-199` | `InPlace/Unique.cpp:158-187,290-291,327-350` and `UniqueResults.cpp:174-190,241-253` (result solve, dead under in-flight C286); `Ownership/Exclusive.cpp` + `Analysis/Ownership/Exclusivity*` (re-derives after counting, grade copies); `Lower/Counting.cpp:134-171` (`idris_rt_is_unique` at run time where that fails); `Contracts.cpp:245-275,326-352` | Boundary result types at the consumer's uses: function results `once` with their claim, region results at `w.uses` (owner: option a), or delete the dead machinery (option b) | (a) cast pairs per linear match/call, rc-exclusive's fresh-result work and grade copies, run-time tests; (b) about 130 lines | L16; L08, L19, L18, L21 | C286 landing; owner's ruling (a) or (b) |
| R2 | Field uses are value uses times declared quantity | `Emit/Bodies.idr:176-178`, `Operations.idr:437` (fields at declared q); `Counting/Ops.cpp:57` and `OpsCon.cpp:107-131` (no product rule on `data.con`) | `Verify/Uses.cpp:125-150` (`fieldReadOnce` tree walk per fold, from `Families/Rules.cpp:31`, `OpsConReads.cpp:97`); `OpsClosures.cpp:263`; `Specialize/Patterns.cpp:135-147` (Enter arm) | Generated product rule on `data.con` (as `ResultUsesMaxOf`), Emit fields at `times w.uses q` | about 30 | L04, L07, L05, L18, L16 | C286 |
| R3 | A cell buffer's single use and claim | `Emit/Bodies.idr:416-420` (cast to bare before `to_tensor`) | `Bufferize/Releases.cpp:207-237` (cast-chain and use-list walk per `to_tensor`) | The field read's grade, kept to the tensor (writable set where the claim is written), or an op taking the cell | about 35 | L12, L16 | owner's choice of carrier |
| R4 | Used once | (pre-C286 casts) | `Analysis/Ownership/Local.h:295-300` `hasOneUse` arm; callers `Unique.cpp:112,150,196` | The grade (already required by `raisable` and `uncountedClaims`) | about 9 | L08 | C286 (same files, in flight) |
| R5 | Closure is once iff a capture is | `Emit/Bodies.idr:773-775,799-801` (captures as bare `Value`); no Idris builder reads `ResultUsesMaxOf` | `Emit/Bodies.idr:452-467` (`holding` matches printed MLIR types) | The spec's trait generated into the Idris builder, or `Val.uses` | about 16 | L16, L03, L18 | none beyond L16's in-flight edits |
| R6 | A matched literal or natural used once | `Emit/Bodies.idr:714,733,735` (`coerce Many`) | rc-exclusive or run-time uniqueness test (conjecture) | The scrutinee's own grade (`lit.match` takes any grade) | 3 casts per match | L16 | C286 |
| R7 | Erased position | (none: two sources of one decision) | `Translate/Closed.idr:410-424` (`eraseArgs` and `rig`); `Growth/Sites.idr:1769-1804` and `Translate/Terms.idr:713-722,798-808,909-915` (two walks) | `ArgumentAt` on C281's tree, from `eraseArgs` | about 6 plus per-binder decisions | L16 | C281 fold (L16eo) |
| R8 | Proved parameter uses (test oracle) | Identity in a discardable `FusedLoc` (`Expect/Quantities.cpp:28-40`) | `Quantities.cpp:79-95` after each pass under `--idr-contracts` | Not settled (owner) | 0 at compile time | L19 | owner |
| R9 | Quantity enum | `Registry/Entry.idr:113` beside `Resolve.idr:205` | `Resolve.idr:211-215,240`; `Profile.idr:328` | `Use` alone | about 12 | L16 | none |
| R10 | Same value through grade changes | casts of R1/R2 | `Verify/Uses.cpp:35-54` beside `sourceOf` `:61-70`; readers in Specialize, Narrow, Bufferize | One `definitionChain` over `sourceOf` | about 10 | L05; L18, L12 | R1 to R3 |

The three findings whose fix deletes the most:

1. **R1**: function and region results at `many`. It feeds a
   program-wide solve after counting, grade copies, run-time uniqueness
   tests, and a result solve in idr-unique-results that the in-flight
   C286 has left computing nothing. It needs the owner's ruling on which
   type holds a fresh result's uses.
2. **R2**: `data.con` admits a `once` field in a `many` value, so field
   folds walk use trees. A generated product rule (the closures already
   have one) and Emit building fields at `times` turn that walk into one
   `hasOneUse`.
3. **R3**: a cell's buffer is cast to the bare carrier, so bufferization
   re-walks casts and use lists to decide `writable`.
