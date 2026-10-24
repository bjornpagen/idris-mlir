<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: coordinator decisions C131 to C279 against the tree

HEAD at start 9f4889dd, at finish d093dbfb. Lanes committed during the
read:
- e72a024f (L12v, `Bufferize/Linear.cpp`);
- 13b0e15e (C280, the proposal);
- 29153f20 (L16em: `Translate/State.idr`, `Choices.idr`, `Programs.idr`,
  `Term.idr`, `Emit/Bodies.idr`, `Emit/Closures.idr`);
- 2d7ee52d (L11z, C279: `Driver/Run.cpp`, `Transforms/Pipeline.cpp`,
  `Pipeline.h`, tests, harness);
- e518e35c (C281, the queue);
- d093dbfb (L17bc: the checker's case trees, `Core/Binary.idr`, `KPlus`
  in the vocabulary).

Every line this report cites in those files was read again after the
commit that touched it (C271's count was re-measured at d093dbfb: 0).
Two verdicts moved with them: C279 (Not done at 9f4889dd, Done at
2d7ee52d) and C257, now read as C281 amends it. The rest did not change.
d093dbfb's `KPlus` is what D131's frontend reading of `plus` waited on;
that reading is not in this range.

Nothing was built, typechecked, generated or run. Each lane commit cited
as evidence says it was built on an export or not built at all. So
*Done* means done in the code, by reading. Ground: *read* (the cited line
was opened at HEAD with `git show HEAD:`) or *measured* (a `git grep -E -c
… HEAD --` count, with its pattern). Committed text was read throughout.
At finish the working tree held uncommitted edits to files some rows
cite: `Spec/Tail/Declarations.idr`, `Spec/Families/Ops.idr`,
`Spec/Grades/*`, `Emit/Bodies.idr`, `Emit/Index.idr`,
`Emit/Operations.idr`, `OpsCon.cpp`, `OpsBigs.cpp`,
`Narrow/Facts.cpp`, `generated.manifest` and `checker/*`. Those rows are
marked *in flight*.

Paths are under `foreign/idr/` unless they start with another top-level
directory. `spec/` is `compiler/spec/IdrisMLIR/Spec/`, and `Translate/`
and `Growth/` are under `compiler/src/IdrisMLIR/Frontend/`. Owners are
per `ownership.json`.

Scope:
- C131 to C263 start from recheck 5's verdicts. Every row recheck 5 left
  non-Done was re-read in the code. Every Done row got one regression
  check (a count or one read line).
- C264 to C279 are checked in full. C273 and C274 were never recorded
  (measured: `grep -rln 'C273\|C274' proposals/ audits/` finds no file).
  They are gaps in the numbering, not decisions.
- Each row is read with its amendments and the later rulings that reach
  it:
  - since recheck 5: C166's amendment (L07v), C203's sharpening (L10x),
    C205's and C218's amendments by D127;
  - D126, which supersedes C235;
  - D129, which settles C262's data form;
  - C268, which amends C262;
  - C281, which amends C257 and was recorded during this read.
- C280 (recorded during the read) amends no row in range and is not
  checked here.

## Not done

### C257, a request's site found by walking, as C281 amends it — Partial (L16)

- **Done.**
  - Obligation 1: the site table sits below `State`.
    `Translate/State.idr:16` imports `Translate/Place.idr`.
    `State.idr:1801-1848` holds `SiteTable`, `DrawnFrom` and `membersOf`
    with `Elem` evidence. `TS.growth : SiteTable` is at `State.idr:1991`.
    (read)
  - D128's walk (cc71ed8b): `Terms.settle`/`bindStands` and
    `Sites.settledWalk` walk the form applied to the call's arguments.
    `lambdasApplied` stays only on the key side: `Closed.idr:352-353`,
    read by `Closed.idr:929,983`, `Terms.idr:552` (`formType`) and
    `Growth/Template.idr:2268`. (read, measured)
- **Not done.**
  - Neither C257's threading nor C281's tree of decided requests exists.
    No module of `Translate/` but `State` imports `Place`. Measured:
    `git grep -n 'import IdrisMLIR.Frontend.Translate.Place' HEAD` finds
    `State.idr:16` and the four growth modules.
  - No run-time copy of `Host.putIn` exists: `git grep -n putIn HEAD --
    compiler/src/IdrisMLIR/Frontend/Translate` finds 0. (measured)
  - The run-time re-check stands: `Frontend/Finite.idr:171-172`
    (`unsound`), `:180-185` (`heightWithin`) and `:190-197`
    (`sizedWithin`). Their calls are at `:215-216`,
    `Translate/Types.idr:606` and `:907`. (read)
- **Owner: L16. Remaining (C281):**
  - The growth model's walk records, at each place, the request the
    translation will make there:
    - its callee;
    - its keyed arguments, computed from the site's term by a run-time
      copy of `Host.putIn` equal to it by `Refl`;
    - its `DrawnFrom` and `HeldAs`.
  - What counts as such a node:
    - a member's body at a use is walked at that use;
    - a dispatch's arms are nodes under its site;
    - a capped position carries its cap as its evidence;
    - a data family's registration is a `Builds` node.
  - The translation folds that tree and computes no request of its own.
  - With the lemma's induction over the model's walk, delete
    `Finite.unsound`, `heightWithin`, `sizedWithin`, their three calls,
    `Types.boundsHold`, and `TS.bounds`/`TS.sizes`
    (`State.idr:1975-1990`).
- **Waits on:** no lane's files (nothing under `Translate/` or `Growth/`
  is uncommitted), and C281 is recorded for the owner's review.
  `audits/p0/verify/handoffs/L16-threading-design.md` predates C281: its
  items 2, 3 and 7 (a subtree carried in `Ctx`, `request` selecting its
  entry) are what C281 replaces. The coordinator revises it before
  dispatch.

### C258, an instance's link keyed by its holes — Not done (L16)

- The link is still `MkLink head (map (map snd) arguments)`, each
  argument `writtenOf writer (term x)` (`Translate/Keys.idr:1124-1125`,
  looked up at `:1126`). `Instances.idr:197-198` pass `term = (.form)`.
  (read)
- The holes travel beside the link, not in it: `Instances.idr:114`
  (`FromDictionary (Maybe Holes) FixedDictionary`), `:125` (`keyOf …
  AsDictionary holes`), `:160`. So two requests that differ only in their
  holes are still one link. (read)
- The model's hole reader exists: `Growth/Sites.idr:265` (`holedAt`).
  (read)
- **Owner: L16. Remaining, with C257/C281:** write the holes into the
  callee's telescope through `callIndices`' level map as a second
  component of the dictionary's written argument. Read them with one
  function, `Sites.holedAt`'s, which both walks reach. Raise a node's
  dictionary parameter by its held position's bound in the universe
  (`boundsOf` skips held positions).

### C256, a request carries what it was keyed from — Partial (L16)

- **Moved since recheck 5:** `NoKey` takes evidence,
  `State.idr:539` (`(0 _ : KeysNothing k) -> AtKey Nothing k`). (read)
- **Done as before:** `WholeKind`, `NeededCut`, `HeldAs`
  (`Translate/Readings.idr`); the dictionary's reduct kept
  (`Cases.idr:510`, `WholeParameter FixedValue`). (read)
- **Not done:** `Request` (`State.idr:585-596`) holds `0 keys` and
  `0 atKey` but no per-position `DrawnFrom` and no `HeldAs`. (read)
- **Owner: L16. Remaining:** C281 puts both in the model's recorded
  request. It closes with C257's item.

### C222, requests and sites one table — Partial (L16)

- The table is one: `TS.growth : SiteTable` (`State.idr:1991`).
- A request is still not a member of it (`State.idr:585-596`), and the
  run-time re-check stands (`Finite.idr:171-216`, `Types.idr:606,907`).
  (read)
- **Owner: L16.** Closes with C256 and C257 as C281 amends them.

### C213 and C217, refused only where a set is unbounded — Partial (L16)

- Five `RuntimeClosure` refusals stand, none naming a member or use-type
  set that no analysis bounds (measured: `git grep -n RuntimeClosure
  HEAD -- compiler/src`, 5 hits; read):
  - `Translate/Terms.idr:684`: "the value of …, which a definition Idris
    does not prove ends computes, at run time, inside the settled form".
    The comment above it (`:672-678`) says its members are ones "the
    program fixes", so it refuses a fixed set.
  - `:777`: "the function …, where a value of a choice the program fixes
    is expected, and which is no member of it" (new since recheck 5).
  - `:1103`: "the type of …, applied inside a settled term, which its
    body does not give".
  - `:1204`: "a value an implementation closes over, computed inside
    another of its own".
  - `Cases.idr:980`: "an implementation's field no compile-time reduction
    reaches".
- The two refusals recheck 5 named were reworded (from
  `Terms.idr:614,1004`). The queue's
  `/tmp/l16ek/repro/form-delay` reaches `:1103` with fixed choices.
- **Owner: L16. Remaining:** under D128's walk (now in), compile each
  situation. Any refusal left names the unbounded member or use-type set
  and its site. Same files as C257's item; dispatch with it or after.

### C228, the core term carries what Emit reads — Partial (L16)

- **Moved:** the translation's internal error for a lambda's result type
  is gone (measured: `git grep -n internal HEAD --
  …/Translate/Terms.idr` lists `:696,802,1636,1736,1833`, none a
  lambda's). Emit still has no `internal`, `assert_total` or
  `believe_me` (measured: 0).
- **Not done:**
  - Emit checks one fact. `Emit/Tensors.idr:160-177` (`Fitting`'s
    `Mismatch`) and `:207` raise `Unfit`. It is carried as `EmitFailed`
    (`Emit.idr:69-76`, `Emit/Monad.idr:55-73`) and reported as an
    internal error at `Frontend/Program.idr:83-85`.
  - The translation re-derives two of the types C228 names:
    `Terms.idr:802` (a force's suspension type) and `:1636` (an
    application's function type). (read)
- **Owner: L16. Remaining:**
  - Carry the slot's type in the term so a value and its slot agree by
    construction, and delete `Mismatch`, `Unfit` and `EmitFailed`.
  - Carry a force's held type and an applied value's function type
    where the translation builds them, and delete the two internal
    errors. The queue notes this needs `Types.coreTypeIn` to return the
    Core and Idris types together.
- **Waits on:** `Emit/Bodies.idr`, `Index.idr` and `Operations.idr` have
  uncommitted edits (a running lane). `Tensors.idr`, `Emit.idr` and
  `Terms.idr` are free.

### C262, no cast follows a call, as C268 amends it — Partial (L16, L12)

- **Done as at recheck 5:**
  - `lib/IR/Func/Verifier.cpp:130` (`resultAxesFit`), called at
    `:199-201`.
  - `lib/IR/OpsArrayShapes.cpp:87` (`tie_shape` answers `Carry::Free`).
  - `include/idr/IR/Func.h:252-277` (`returnable`, `returnedAs`).
  - Emit's results at `returned` (86fe84cf). (read)
- **The data form is settled by D129** (B\*). It is no longer
  Open-owner. The call verifier's layout check is in:
  `lib/IR/Tail.cpp:378` (`verifyLayouts`), gated from Graded on
  (`:263-269`, C265). (read)
- **Not done:** C268's tie. Emit's `tie` still reads each unstated
  dynamic axis off the array: `Emit/Tensors.idr:643` (`sizeAt l xv (j,
  Dynamic)`, a `tensor.dim`, `:118`), with the doc's "else read from it"
  at `:626`. (read)
- **Remaining:** C268's row below.

### C264, the e-graph's computed constants — Partial (L14, L18)

- **(a) Done.** Strings and bigs share the arena's byte budget.
  `Transforms/EGraph/Engine.h:61-64`, `Build.cpp:82` (`constantBytes =
  budget * bytesPerNode`), `Nodes.cpp:421-424` (a constant past it is
  dropped; its op stays applied). (read)
- **(b) Done in the code.**
  - `spec/Core/Admitted.idr:60` (`UpFold = UpstreamFold |
    ComputedOnDoubles | NeverFolded`).
  - The list: addf, subf, mulf, divf, negf, cmpf, sitofp, uitofp
    (`spec/Ops/Shapes.idr:331-378`), floor and ceil (`:446,450`).
  - Computed by `APFloat` at nearest-even in `EGraph/Values.cpp:333-409`,
    checked when the compiler is built (`EGraph/Rules.cpp:75`). (read)
- **(b)'s text differs from the code** (coordinator):
  - The row names `math.sqrt` as computed. It is `UpstreamFold` and left
    applied, since upstream's fold calls the host's `sqrt`
    (`Shapes.idr:398-403`; aaa578c6 says so).
  - The row names `rem` and the conversions. `remf`, `fptosi` and
    `fptoui` are not admitted (`Shapes.idr:470-479`).
- **(c) Partial.**
  - Done: a computed string or big stands as static data at a borrowed
    runtime operand and a constructor field (`EGraph/Elaborate.cpp:30-42`,
    4510a414).
  - Not done (the settled (ii)): a call argument still takes the class
    at its own type with the computing op applied, because "a round that
    only simplified is a function's last and the pipeline's own runs of
    the graph have no specializer after them" (`Elaborate.cpp:43-48`;
    `Optimize/Component.cpp:16-18`).
  - Not done: values carrying the constant on through casts, guards and
    yields are not re-graded (`Elaborate.cpp:49-52`). (read)
- **Owners:** L14 (`EGraph/Elaborate.cpp`) and L18
  (`Optimize/Component.cpp`, `Specialize/Signatures.cpp`).
- **Remaining:**
  - Place a computed string or big as static at a call argument, with a
    specializer round after the graph (idr-optimize does not end a
    member on a round that only simplified while the graph made a static
    argument; the standalone graph steps get that round too) so the
    callee is keyed by hold (D89).
  - `Signatures::edit` re-grades results as well as parameters.
  - Re-grade at write-back the values that carry the constant to
    any-hold ops.
  - This is the queue's "From L14z" item.
- **Waits on:** L18x, which holds `Specialize/`.

### C268, `tie_shape` names the axes it ties — Not done (L12, L16, L18)

- **Spec:** `spec/Arrays/Memory.idr:400-440` (`tieShapeOp : Op 2 1 0 0`,
  `ins = [value, variadic dims]`, `attrs = []`). Its sizes cover every
  dynamic dimension in order; no axis is named. (read)
- **C++:** `OpsArrayShapes.cpp:72-78` refuses a size count other than
  `getNumDynamicDims()`. `:104-128` (reify, value bounds) read the sizes
  by position. (read)
- **Emit:** `Emit/Tensors.idr:619-660`. The read at `:643` and the doc
  at `:626` are as in C262. (read)
- **Owners:** L12 (`spec/Arrays/Memory.idr`, `OpsArrayShapes.cpp`), L16
  (`Emit/Tensors.idr`), L18 (the specializer's re-inference,
  `Specialize/Consumer.cpp`).
- **Remaining:**
  - L12: give the tie an attribute naming its tied axes, with sizes for
    those alone, read by inference, reify and value bounds.
  - L18: the re-inference reads the named axes.
  - L16: `tie` states only the axes something states, deletes the
    `sizeAt` read and "else read from it", and emits no tie where nothing
    is stated.
  - Reproducers: `/tmp/l16ef/repro/successor-axis`, `literal-index`.
- **Waits on:**
  - L12: `Arrays/Memory.idr` itself is free, but the regenerated outputs
    and `generated.manifest` are uncommitted in the working tree (a
    running specification lane), so its regeneration follows that lane.
  - L18: L18x.
  - L16: L12's half.

### C272, an erased index an index parameter of the instance — Not done (L16)

- The instance key still erases every index of a keyed type argument.
  `Translate/Types.idr:321-365` (`eraseIndices` sends each `Index` role
  to `Erased EmptyFC Placeholder`). `Instances.idr:493-502` offers
  `IndexParam` only for the instance's own erased binders that occur as
  an index only. So `(.)` at `b = Vect n Int` takes no index parameter,
  and no call passes `v0`. (read)
- The lanes' own measure has 3 internal errors over 429 fixtures,
  attributed to C272 (1bc9c325, 29153f20). That is their measure, not
  this read's.
- The reproducer `/private/tmp/l16ei/repro/compose-index/Main.idr`
  exists. No `tests/` fixture states it (measured: `ls tests | grep -i
  compose` finds none).
- **Owner: L16. Remaining:**
  - An index `argumentKey` erases from a keyed argument becomes an
    `IndexParam` beside the `IndexOnly` ones.
  - Each call passes its term (`Terms.idr`'s operands).
  - Add the fixture.
- **Waits on:** nothing held. It shares `Types`, `Instances`, `Keys` and
  `Terms` with C257/C281, so dispatch it with that lane or after it.

### C156, the e-graph's nodes per op measured — Partial (stage 1)

- `spec/Pipeline/Pipeline.idr:296-304`: `nodesPerOp = 64`, "Not yet
  measured". Unchanged. (read)
- **Owner:** L03, measured by L14/INT on the owner's machine.
- **Remaining:** measure the nodes made per op on the stage-1 module, and
  replace 64 and "not yet measured" with that figure, its build and its
  input.

### C201, the tools' stacks and the outside-code margin measured — Partial (stage 1)

- `CMakeLists.txt:262,279,297,330`: every target entry still calls
  `idris_mlir_unmeasured_stacks()`, defined at `:216-223`. Unchanged.
  (read)
- **Owner:** INT, on the owner's machine (L11 measuring).
- **Remaining:** measure `IDRIS_MLIR_TOOL_STACK_BYTES`,
  `_TOOL_SIGNAL_BYTES` and `_OUTSIDE_STACK_BYTES` per target, record each
  in its entry with its build and input, and delete that entry's call.

## Superseded

- **C149, C163**, by C165: patch 78 is not applied. `upstream/README.md:143`
  says "not carried since 2026-10-21 (C165…)", and the submission
  directory stays. (read)
- **C185**'s claim level, by D122:
  `lib/Transforms/Bufferize/Releases.cpp:59` (`bufferClaim =
  idr::Unique::Self`). (read)
- **C212**, withdrawn:
  - `compiler/checker/src/Core/Termination/SizeChange.idr:265`
    (`allFins` once per search). (read)
  - `libs/mlir-array` has no `Nat`-indexed read (measured: 0).
- **C225**, by D113, then D119 and C237: no `assert_total` or
  `assert_smaller` in the checker's parsers (measured: 0).
- **C230, C232**, withdrawn by D116.
- **C235**, moved here from Done, by D126 (2026-10-23):
  - D126 rules that each of our types answers through an interface method
    the specification declares. C235 chose a fold over a closed list
    because "a type interface is MLIR's answer for an open set".
  - aaa578c6 (round 3-A) removed `Match.h`'s type fold and
    `IdrDialect.h`'s `DialectTypes`. Measured: `git grep -n
    'foldTypes\|matchTypes\|DialectTypes\|foldDialect' HEAD -- foreign/idr`
    finds only the bytecode DSL's `DialectTypes<"Idr">`
    (`IdrBytecode.td:85`) and the tblgen reader of it.
  - C235's other half, `foldDialect`'s `isa` chain deleted, holds.

## Done

Each Done row from recheck 5 got one regression check at HEAD. None
regressed. Where a line moved, the new one is given.

C131 to C185:

- **C131**: `harness/Facts.idr:53` (`readEnding : String -> Maybe Ending`).
  No test script remains (measured: `git ls-files | grep -E
  '(run|e2e|differential|actions|lit|profile)\.sh$'` finds `bench/run.sh`
  only).
- **C132**: `harness/Programs.idr:258-260`.
  `tests/actions-skip-programs` is gone. (measured)
- **C133**: nine `tests/scale-*`, and no `defunc-tag-limit` (measured).
- **C134**: `harness/harness.ipkg:9` (`depends = idris-mlir-spec`).
  (read)
- **C135**: `harness/Lit.idr:4-10,174` (`%differential`). (read)
- **C136**: a placement in §7, no code.
- **C137**: `tools/idris-mlir-tblgen.cpp:21,2034`. (read)
- **C138, C177**: `runtime/Alloc/Peaks.cpp:43` (`FrameBoundExceeded`),
  `spec/Runtime/Endings.idr:155`, and `tests/runtime-frame-bound`.
  (read)
- **C139**: one decider, `lib/IR/Tail.cpp:212-241` (`tailsOf`), as C203
  sharpened it. (read)
- **C140**: `spec/Lifetimes/Kind.idr:25`, `lifetime.forget`
  (`Declarations.idr:696`). No op carries the trait
  `AutomaticAllocationScope`: its 11 hits are the trait's declaration,
  the upstream frame resource and the lowering's parent lookups.
  (measured)
- **C141**: no patch carried. (`ls upstream`)
- **C142**: the proposals' text. (read)
- **C143**: `spec/Grades/Declarations.idr`. (read; *in flight*)
- **C144**: no undecided hold. The 14 hits of `Undecided|…` are
  `Boundary.idr:355`'s `Headed` and a unit test's fault name, both
  unrelated. `OpsArrayFusion.cpp:132` (`countingAt`). (measured, read)
- **C145, C146, C147, C160**: `spec/Lifetimes/Declarations.idr` (`reserve`,
  `OnStack`/`InChain` at `:82`). (read)
- **C148**: `spec/Lifetimes/Kind.idr:25` (`Home Nat`). (read)
- **C150**: `compiler/src/IdrisMLIR/Term.idr:417` (`ReadBack`). (read)
- **C151**: a measurement record.
- **C152**: `include/idr/IR/Generated/IdrOps.td`, 8 `MemRead<Idr_ContentsResource>`.
  (measured)
- **C153**, moved:
  - `spec/Pipeline/Pipeline.idr:294`: "Rules from the specification run
    in rounds, … a rebuild restoring congruence after each". Generated
    into `IdrPasses.td` (aaa578c6).
  - "applied at insertion" is gone (measured: 0 under `foreign/idr` and
    `compiler/spec`).
- **C154**: no library body builds a `Dec` (measured: 0).
- **C155**: `spec/Ops/Numeric.idr` laws (18 hits). (measured)
- **C157**: no greedy driver, canonicalization pattern or canonicalizer
  (measured: 0).
- **C158**: `spec/Ops/Values.idr:7` (`idr.platform.os`). (read)
- **C159**: `lib/IR/Func/Values.cpp:95` (`admitsWrite`). (read)
- **C161**: `IdrOps.td:2523` (`isCountedValue`). (read)
- **C162**: `lib/IR/Grades.cpp`. (read)
- **C164**: `tests/spec-current/run`. (read)
- **C165**: as C149.
- **C166**, with L07v's amendment, which is done:
  - `lib/IR/Control/LiteralMatch.cpp:65-68`: a literal case binds the
    scrutinee, `getRegionScrutinee` returning `Equals{key}`.
  - `lib/Analysis/Ranges.cpp:112` (`excluding`). (read)
- **C167, C176**: `lib/IR/Tail/Destinations.cpp`. (read)
- **C168**: `runtime/idris_rt.h`. (read)
- **C169**: `runtime/Strings/Simd.h:6` (final class, `static_assert`).
  (read)
- **C170, C181, C182**: `outers` in `spec/Families/Ops.idr:95` and
  `spec/Grades/Declarations.idr` (*in flight*).
  - Moved: the check is now the `StatesOuters` templates
    (`include/idr/IR/Lifetimes.h:239-295`).
  - It is called by `verifyOuters` at `Control/Joins.cpp:118`,
    `Counting/Ops.cpp:161` and `Families/Refinement.cpp:73`. (read)
- **C171, C179**: `spec/Tail/Declarations.idr:20` (`dest.answer`).
  (read; *in flight*)
- **C172**: `tools/bootstrap.sh`. (read)
- **C173**: `InPlace/UniqueResults.cpp:338` (`raiseClaims`). (read)
- **C174**: `Translate/Choices.idr:13`. (read)
- **C175**: `Frontend/Finite.idr`. (read)
- **C178**, moved:
  - `include/idr/Analysis/Solver/TypeGraph.h:92` (`footprint::DenseMap<Key,
    unsigned> index`).
  - `include/idr/Analysis/Ownership/ExclusivityDetail.h:123`
    (`footprint::DenseMap<Key, Anchor> keys`), both from fc6fb0f8.
  - 28 plain `DenseMap`s are left (measured). They are in the lowering,
    the driver, layout numbering, diagnostics and content-keyed tables;
    `TypeGraph.cpp:180` is a component-sized witness path.
- **C180**: `spec/Arrays/Memory.idr:320` (`array.place_copy`). (read)
- **C183**: `compiler/checker/src/Core/TT/Stored.idr`. (read)
- **C184**: no header beside a `.cpp` (measured: 0).

C186 to C224:

- **C186**: `runtime/Alloc/Peaks.cpp` and `tests/shipped-accounts`. (read)
- **C187**: `upstream/99-function-interface-edits/` and
  `tests/upstream-function-interface-edits`. (`ls`)
- **C188**: no sharing claim written by the frontend (measured: 0).
  `InPlace/Rule.cpp:132` (`boundaryAsks`). (read)
- **C189**: `Tail/Frames.cpp:158` (`runsCallsOnFrames`), and
  `Lifetimes/Decide.cpp`. (read)
- **C190**: one `raiseClaims`. (read)
- **C191**: `EGraph/Engine.h:20-23` (a built node's interval from its
  kind's range function). (read)
- **C192**: `spec/Counting/Declarations.idr:31` (`own.adopt`). No
  `ownAdoptOp` (measured: 0).
- **C193**: `Registry/Recognized.idr`, `Registry/Faster.idr`. (read)
- **C194**: `spec/Closures/Memo.idr`. (read)
- **C195**: `Ownership/Exclusive.cpp:138` is the pass. `Quantities.h:44`
  (`Token`). (read)
- **C196**: `spec/Ops/Platform.idr`. (read)
- **C197**: `spec/Core/Op.idr:303` (`GuardKind`), `spec/Ops/Checks.idr:338`
  (`guardOpOf`). (read)
- **C198**: `spec/Core/Admitted.idr:60`. (read)
- **C199**: `Makefile` (`knowngen`), with no manifest entry (measured: 0).
- **C200**: `include/idr/Support/Match.h:179,200` (`static_assert(named,
  "no case of a match takes every type")`; `eachNamed` was renamed).
  (read)
- **C202**: `Ownership/Facts.h:353` (`upstreamElement`). (read)
- **C203**, with L10x's sharpening, which is done:
  - The decider is one downward walk, `tail::tailsOf` (`Tail.cpp:212-241`).
  - No `inTailPosition` and no `decide(CallOp)` remain (measured: 0;
    `Specialize/Calls.h:102`'s `decide` is the specializer's own).
  - `decideTails` runs in the e-graph's write-back (`Elaborate.cpp:452`),
    inlining (`Inline.cpp:160`, `InlinePass.cpp:50,62`), capture drops,
    raising (`Raise.cpp:161`), narrowing, TRMC and frames.
  - Emit writes `nontail` (`Emit/Bodies.idr:598`). (read)
- **C204**: no `index_switch` in `compiler/src` (measured: 0).
- **C205**, as D127 amended it, moved:
  - `EGraph/Engine.h:14-31`: a constant is one of four values (integer,
    string bytes, Double bits, big) until the write-back makes its
    attribute.
  - `EGraph/Values.cpp:1-27` (the one fold's value instance).
  - The never-folded list is checked when the compiler is built
    (`EGraph/Rules.cpp:72-75`). (read)
- **C206**: `lib/IR/Tail.cpp:52` (`carriesOn`). (read)
- **C207, C208, C214, C215**: their files stand. (read)
- **C209**: `include/idr/IR/FlowEdges.h:203` (`partOf`). (read)
- **C210**: `Driver/Main.cpp:95`. (read)
- **C211**: `Ranges.cpp:112`. (read)
- **C216**: `compiler/checker/src/Idris/Syntax/Tree.idr`. (read)
- **C218**, moved: its first settlement as D127 reverses it (above), and
  its second (`idr.refusal` bare) stands.
- **C219**: `Translate/State.idr:1035` (`Holding = AMember | NoMember |
  ByInstance`).
  - Moved: the wrapper written twice is now one. `Growth/Sites.idr:1044-1045`
    (`holdingAt`) normalises its type, then asks `Types.typeHolding`
    (`Types.idr:432-433`); `Sites.idr:1160` asks it too.
  - No `holdingOf` remains (measured: 0). (read)
- **C220**: `Translate/Boundary.idr`. (read)
- **C221**: `Translate/Contraction.idr:5`. (read)
- **C223**: `Growth/Graph.idr:21` (`heldCount`). (read)
- **C224**: `Growth/Graph.idr:1901` (`OneValue`). (read)

C225 to C263:

- **C226**: `foreign/idr/CMakeLists.txt:21-44` (NDEBUG taken out, an LLVM
  without assertions refused outside the typecheck build).
  `tools/bootstrap.sh:926`. (read)
- **C227**: `Growth/Template.idr:37` (`SEta`). (read)
- **C229**: no `Syntax/` manifest entry and no Python under `tools/`
  (measured: 0, 0). `tests/dialects-current` is present.
- **C231**: `Translate/Instances.idr:451` (refused `ValueType` at the
  request). `Growth/Implementations.idr:42` (`staticsOver`). (read)
- **C233**: no live `compiler/idris/` reference (measured: 0). No
  `extract-idris` and no `upstream/fork-*` (`ls`).
- **C234**: `Instances.idr:855` (`SignedAt`). (read)
- **C236**: `Analysis/Solver/Extraction.h:18-20`. (read)
- **C237**: no `assert_total`/`assert_smaller` in the parser libraries
  (measured: 0). `Idris/Parser.idr:24` (`%default total`). (read)
- **C238**: `Analysis/Solver/Schedule.h:6` (`parallelForEach`), no
  `std::atomic` (measured: 0).
- **C239**: `Func/Verifier.cpp:152` (`extentsFit`). No `extentDim`
  (measured: 0).
- **C240**: `Emit/Bodies.idr:4` (`idr.join`, `idr.loop`) and
  `Optimize/Contify.cpp:6`. (read)
- **C241**: `Func.h:258` (`staticSizeAt`), `:305` (`meets`),
  `Grades.h:120` (`holdFitsMask`). (read)
- **C242**: `State.idr:92` (`StaticReading`), `Proof/Covers.idr:1249`.
  (read)
- **C243**: §5.2. (read)
- **C244**: `spec/Tail/Declarations.idr:184` (`Carry`; *in flight*). No
  carry reader casts to `DataReindexOp`. The one `dyn_cast<DataReindexOp>`
  (`Specialize/Open.cpp:403`) re-grades a value, not a tail (see
  outside the range). (read)
- **C245**: `tools/bootstrap.sh:1659` (`flock`), `tools/host.sh:124`
  (`wait4`). (read)
- **C246**: no `.awk` under `tests/`. `harness/lib/harness.sh` is 287
  lines of glue. (measured)
- **C247**: `spec/Core/Interfaces.idr:100` (`StructureOpInterface`), asked
  at `Analysis/IdentitiesRecord.cpp:201`. (read)
- **C248**: `Term.idr:1418` (`RunHead`). No `data All` in `compiler/src`
  (measured: 0).
- **C249**: `State.idr:606` (`kindsOf` a `Vect` of the applied arity).
  (read)
- **C250**: `Conversion/Elements.cpp:110`. (read)
- **C251**: a counting rule.
- **C252**: `spec/Closures/Declarations.idr:103` and `IR/Constants.cpp:90`.
  (read)
- **C253**: no `!idr.token` or our own `TokenType` (measured: 0).
  `ReuseTokenType` has 22 hits.
- **C254**: `Growth/Graph.idr:37` (`LandingTable`). No `DropsReach` or
  `thenNothing` (measured: 0).
- **C255**: `State.idr:1097` (`DefinitionRead`). (read)
- **C259**: `State.idr:169` (`FixedDictionary`), `Cases.idr:510`. (read)
- **C260**: `State.idr:1283` (`SolvedAs`). `Closed.idr` has no `internal`
  (measured: 0).
- **C261**: `Programs.idr:461` (`callsOf`), `Term.idr:1919` (`joinsIn`).
  No `throughAll` or `internal` in `Programs.idr` (measured: 0).
- **C263**: `Instances.idr:159` (`TypeParam`). The three fixtures are
  present (measured).

C264 to C279, checked in full:

- **C265**:
  - The stage fact: `spec/Pipeline/Stage.idr:104,166-174,211-214`
    (`StageTailLayouts`, pending at Higher and First), generated into
    `Generated/StageFacts.h.inc:52,150-153`.
  - The gate: `lib/IR/Tail.cpp:263-269` (`layoutsAgree`), read by
    `verify(FuncOp)` (`:338-346`). Before Graded, a re-packed tail is no
    tail (`:243-249`). (read)
- **C266**:
  - The stretch is cut where `mayHold` refuses, each side lent apart,
    and an alias re-made across a cut (`remakeAlias`):
    `Transforms/Lifetimes/Lend.cpp:8-16,285-345,383`.
  - The one helper serves frames too (`IR/Lifetimes/Loans.h:14,138`,
    `Tail/Outline.cpp:136`).
  - The two residuals are internal errors naming their op (`Lend.cpp:296-297,328-332`).
  - Adoption follows flow edges (`IR/Lifetimes/Loans.cpp:130-143`;
    80f6e719). (read)
- **C267**, with its sharpening:
  - `Specialize/Open.cpp:3-37` holds the one rule: a caller's closed
    result that cannot agree with its tail callee's is marked open
    (D130's `LayoutMark`, `spec/Families/Layout.idr:40`), and callers
    convert after their call (`convertCall`, `:727`).
  - It is decided once per function before the wave
    (`Transforms/Optimize.h:6-7`, `OptimizeScheduler.h:98-99`,
    `Open.cpp:967`). (read; 410c5dcd)
  - `Specialize/` is held by L18x.
- **C269**:
  - `spec/Counting/Declarations.idr:309-343` (the shared region's value
    at many, `areTypesCompatible` declared).
  - `IR/Counting/Takes.cpp:233-288` (forwarded at `atUses(value, Many)`).
    No `lin.cast` (19307ee9). (read)
- **C270**:
  - `count.drop` takes `countedMany` (`spec/Counting/Declarations.idr:79-85,208`).
  - `EndsOwner` is on drop, take, unpack, take_into and match_unique
    (`:209,256,278,298,337`).
  - It is read by `IR/Verify/Linearity.cpp:346-366` and
    `Counting/Flow.cpp:148`.
  - Placement takes a once value apart (`PlacementRewrite.cpp:56,208`).
    (read)
- **C271**:
  - `compiler/checker/src/TTImp/ProcessTransform.idr:21-47` checks both
    sides and stores nothing.
  - No `addTransform` or `transforms` (measured: 0 under
    `compiler/checker/src`).
  - `tests/pragma-transform/expected` reads `unsupported (pragma)`.
    (read; fc306c2c)
- **C275**:
  - One function on types: `lib/IR/Families/Repacks.cpp:271-280`
    (`builds`), `:291-311` (`fieldReadBuilds`), making no type (no
    `determinedFields` in the file).
  - Asked by the reindex verifier (`Families/Refinement.cpp:63`), both
    flows (`FlowOps.cpp:137,152`) and the lowering
    (`Conversion/Lower/Repack.cpp:280`).
  - The op-member form is the queue's L04y item, waiting on L16en. It is
    not an obligation of C275. (read)
- **C276**:
  - `lib/IR/Families/Matching.cpp:24-53` (`readInstance` takes a term
    with an opaque index as the pattern's term where narrowing is
    allowed). It is reached by the scope rule (`ScopeWalk.cpp:252-265,347-353`).
  - Writable terms are checked as before (`:43-44`).
  - `tests/opaque-cast-closed-copy`. (read)
- **C277**:
  - `Specialize/Open.cpp:437-484` (`keyGivenBack`, from the published
    gives-back facts), asked by `Consumer.cpp:314` and `keyCalls`
    (`Open.cpp:886-906`).
  - `lowerParameters` (`:807-874`) lowers a member's parameter, keying
    no copy inside the component. (read)
- **C278**:
  - `include/idr/Analysis/Identities.h:76-112` (may facts beside must),
    read at `Open.cpp:455-483`.
  - A copy in its caller's component is lowered as a member, its
    signature restated (`Open.cpp:807-816`, `SpecializeState.h:221-223`).
  - One `families::takenTypes` (`Substitute.cpp:453-470`), asked by
    `Ownership/Exclusive.cpp:120` and `InPlace/UniqueResults.cpp:297`
    (a0d5c9c3).
  - a0d5c9c3 says the copy-in-component case has no test. (read)
- **C279**, done at 2d7ee52d during the read:
  - Every slice runs idr-target first (`lib/Transforms/Pipeline.cpp:77-86`).
  - The driver's own `addPass` is gone, and a lowered module takes
    idr-target alone (`Driver/Run.cpp:162-164`).
  - `moduleKindOf` holds no target check (measured: `git grep -n
    OtherTarget HEAD -- foreign/idr/lib/Driver`, 0).
  - No test names `idr-target` (measured: 0 under `tests harness tools
    Makefile bench`). The one module writing a target is
    `tests/other-target-refused/run:40`'s planted witness (C251).
  - The one target option is `print-target-triple`
    (`Driver/Options.cpp:127`). (read)
  - One sentence lags: `spec/Pipeline/Pipeline.idr:205-206` ("The driver
    runs it first"), queued for L03 in e518e35c.

## Count

147 decisions (C131 to C279; C273 and C274 are unrecorded), each read
with its amendments:

| | C131-C185 | C186-C224 | C225-C263 | C264-C279 | all | recheck 5 (C131-C263) |
|---|---|---|---|---|---|---|
| Done | 51 | 34 | 30 | 11 | 126 | 112 |
| Partial | 1 | 4 | 4 | 1 | 10 | 13 |
| Not done | 0 | 0 | 1 | 2 | 3 | 1 |
| Regressed | 0 | 0 | 0 | 0 | 0 | 0 |
| Superseded | 3 | 1 | 4 | 0 | 8 | 7 |

- **Moved since recheck 5:**
  - Partial to Done: C153, C178, C205, C218.
  - Done to Superseded: C235 (D126).
  - Open-owner to settled: C262's data form (D129).
  - C256 moved within Partial (`NoKey`'s evidence).
  - C228 moved within Partial (the lambda's internal error gone).
  - C257 moved within Partial (site table below `State`, D128's walk),
    and is now amended by C281.
  - Moved within Done: C166 (its amendment), C170 (the check moved into
    templates), C200, C203 (its sharpening), C219 (one wrapper).
- **Partial:** C156, C201, C213, C217, C222, C228, C256, C257, C262,
  C264.
- **Not done:** C258, C268, C272.
- **Superseded:** C149, C163, C185, C212, C225, C230, C232, C235.
- **Need stage 1** (a measurement, no code): C156, C201.

## Dispatchable items, by owner

**L16** (frontend; nothing under `Translate/` or `Growth/` is
uncommitted at e518e35c):
1. **C257 as C281 amends it, closing C256 and C222.** The growth model
   records at each place the request decided there (callee; keyed
   arguments from the site's term by a `Refl`-equal run-time
   `Host.putIn`; `DrawnFrom`; `HeldAs`; a cap as evidence; dispatch arms
   and `Builds` nodes), and the translation folds the tree. Then delete
   `Finite.idr:171-216`'s three functions, their calls at
   `Types.idr:606,907`, `Types.boundsHold`, and `TS.bounds`/`TS.sizes`.
   - Evidence: the C257 row.
   - Waits on: C281 is recorded for the owner's review, and the
     threading design is revised to C281 (coordinator).
2. **C258, with item 1.** Holes in the link's argument through
   `callIndices`' level map (`Keys.idr:1124-1126`, `Instances.idr:114,125,160`).
   One reader, `Sites.holedAt` (`:265`). Held positions raised in the
   universe.
3. **C272, with or after item 1.** An index `eraseIndices`
   (`Types.idr:321-365`) erases becomes an `IndexParam` beside
   `Instances.idr:493-502`'s, and the call passes its term (`Terms.idr`).
   Add a fixture from `/private/tmp/l16ei/repro/compose-index`.
4. **C213, C217, with or after item 1.** Compile the five situations
   refused as `RuntimeClosure` (`Terms.idr:684,777,1103,1204`,
   `Cases.idr:980`). Any refusal left names an unbounded set and its
   site. Reproducer: `/tmp/l16ek/repro/form-delay`.
5. **C228.**
   - Slot types carried in the term. Delete `Mismatch`
     (`Emit/Tensors.idr:160-177,207`) and `Unfit`/`EmitFailed`
     (`Emit/Monad.idr:55-73`, `Emit.idr:69-76`, `Program.idr:83-85`).
   - A force's held type and an applied value's function type carried.
     Delete `Terms.idr:802,1636`.
   - Waits on: the running lane's uncommitted `Emit/Bodies.idr`,
     `Index.idr` and `Operations.idr`.
6. **C268's Emit half (C262).** `Emit/Tensors.idr:619-660` states only
   stated axes. Delete the `sizeAt` read at `:643` and "else read from
   it" at `:626`. Waits on item 7.

**L12:**
7. **C268.**
   - `tie_shape` names its axes, with sizes for those alone
     (`spec/Arrays/Memory.idr:400-440`).
   - The count check (`OpsArrayShapes.cpp:72-78`) and reify and value
     bounds (`:104-128`) read the named axes.
   - Waits on: the running specification lane's uncommitted
     `generated.manifest` and generated outputs, for the regeneration.

**L18** (both wait on L18x, which holds `Specialize/`):
8. **C268.** The specializer's re-inference (`Specialize/Consumer.cpp`)
   reads the named axes, after item 7.
9. **C264(c).** A specializer round after the e-graph where it made a
   static call argument (`Optimize/Component.cpp:16-18`; the standalone
   graph steps too). `Signatures::edit` re-grades results.

**L14:**
10. **C264(c).**
    - A computed string or big placed static at a call argument (with
      item 9).
    - Values carrying it on through casts, guards and yields re-graded
      at write-back (`EGraph/Elaborate.cpp:43-52`).

**L03:**
11. **C156** (stage 1, owner's machine). Replace `nodesPerOp = 64` and
    "Not yet measured" (`Pipeline.idr:296-304`) with the measured figure,
    its build and its input.
12. **C279's sentence.** `Pipeline.idr:205-206`: every slice of the
    pipeline runs idr-target first. Already queued.

**INT:**
13. **C201** (owner's machine). The three stack sizes per target,
    recorded in each entry. Delete the calls at `CMakeLists.txt:262,279,297,330`.

**Coordinator:**
14. **C264(b)'s text.** It names `math.sqrt`, `rem` and the conversions
    as computed. At HEAD:
    - `sqrt` is `UpstreamFold`, left applied (upstream's fold calls the
      host's libm);
    - `remf`, `fptosi` and `fptoui` are not admitted (`spec/Ops/Shapes.idr:398-403,470-479`).
    - Correct the row to the list the specification holds, or route a
      change to the list.
15. **The threading design.** Revise
    `audits/p0/verify/handoffs/L16-threading-design.md` to C281 before
    dispatching item 1.

## Queue items found done (strike from `L16-queue.md`)

- **Recheck 5's §6 N1**, the tail decider's climb: no `inTailPosition`,
  and `decideTails` is in the passes (C203).
- **N2**, the cycle rule in four places: `Analysis/Solver/Components.h:50`
  (`isCycle`), fc6fb0f8.
- **"After round 3-A", L14y's group:**
  - C264(b)'s float ops computed by `APFloat` (`EGraph/Values.cpp`);
  - C264(c)'s reading settled and carried out for borrowed operands and
    fields (4510a414);
  - `Analysis/Constants.cpp`'s `sortedIds(NeverFolded)` gone (`:30-37`
    asks the generated list with `listed`; measured: no `sortedIds`).
- **"From spec round 4" and "From L02x":**
  - `Term.Termination`'s `Acyclic` and its writers are gone (29153f20;
    measured: no `Acyclic` under `compiler/src`).
  - The specification's and the C++'s `Acyclic` termination is gone (the
    one hit is `Families/Declaration.h:200`'s unrelated `Containment`).
  - `OtherTarget` has a test (`tests/other-target-refused`).
- **"From L21x":** the `OtherTarget` rule exists and is taken, and
  `Run.cpp`'s lowered checks are gone (C279). Only `Pipeline.idr:205-207`
  is left, re-queued.
- **"From L04w":** `tests/reindex-builds-told-apart`'s RUN line names no
  pass and writes no target (2d7ee52d).
- **"From L18w":** `Open.cpp`'s grade helper now asks `families::builds`
  (`Open.cpp:139-148`).
- **"From L12x":** the flow no longer makes types on a worker (C275). The
  op member is L04y's, still open.
- **"D130 and D131":** C265's gate (`Tail.cpp:263-269`) and C267's rule
  (`Open.cpp`) are in. The layout mark and the Nat sum are declared
  (`spec/Families/Layout.idr:40`, `Terms.idr:13-18`). The frontend's
  `plus` reading is still open. The `KPlus` it waited on joined the
  checker's vocabulary in d093dbfb.
- **"C269, after L04x releases the specification"** (19307ee9).
- **L05x**, done as C266 (80f6e719). **L11z**, done (2d7ee52d).
- **L18t's leftovers under C278** (a0d5c9c3).
- **Recheck 5's "seen outside the range":** `MLIR.idr:148` now writes
  `TokenType` as `"token"`.
- **C219's one-line wrapper written twice** (queued at 9f4b74b9):
  `Sites.holdingAt` asks `Types.typeHolding` (`Growth/Sites.idr:1044-1045`).

## Seen outside the range

- `Frontend/Finite.idr:224` (L16): still an internal error for "an
  instance requested again as new on its own chain". The threading
  design says it needs an instance table whose lookup returns evidence.
- `Transforms/Lifetimes/Lend.h:63-67` (L05): still shares a holder into a
  read whose alias leaves the loan. This is not a loan changing a count;
  it belongs to D124's audit.
- `Specialize/Open.cpp:403` (L18): the opening's re-grade names
  `DataReindexOp` by `dyn_cast` beside the `InferTypeOpInterface` walk
  under it. D126 asks a typed walk or an interface.
- C280 (recorded during this read, the heap's `Filling` child) is
  outside this range and not checked.
