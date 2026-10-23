<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5: coordinator decisions C131 to C263 against the tree

HEAD at start 17725fdd, at finish cb5cd6fb. Lanes committed during the
read (2bcbd726, 16ac96c4, 59dcc964, cb5cd6fb); each cited line was read
as it stood when it was opened. Nothing was built, typechecked, generated
or run. Ground: *read* (the cited line was opened) or *measured* (a
`git grep`/`ls` count, with the command). Paths are under `foreign/idr/`
unless they start with another top-level directory; `spec/` is
`compiler/spec/IdrisMLIR/Spec/`. Owners per `ownership.json`. Rows whose
evidence sits in a file a writing lane holds are marked *in flight*;
where the working tree had uncommitted edits (`Growth/*`,
`Translate/Place.idr`, `Translate/Terms.idr`, `Fold.h`, `EGraph/*`), HEAD's
committed text was read.

C131 to C224 start from recheck 3's verdicts
(`recheck3/decisions-C81-C160.md`, `decisions-C161-C224.md`); no decision
of that range regressed since f5736f12. C225 to C263 are checked in full.
Each decision is read with its sharpenings and amendments, and with the
rulings that reach it: D113, D116, D119 (C225, C230, C232), D115 and D120
(C226), D122 (C185), D123 (C153), D124 (C239's graded limit), D126
(C235, C244, C247), D127 (C205, C218), D128 (C257).

## Not done

### C257, a request's site found by walking — Partial, in flight (L16ee)

- Done: one structural `Place` below `State`
  (`compiler/src/IdrisMLIR/Frontend/Translate/Place.idr`, HEAD's text:
  `PlaceStep`, `WalkMode`, `Place = SnocList PlaceStep`), imported by the
  growth modules (`Growth/Sites.idr:46`, `Graph.idr:57`, `Heads.idr:63`,
  `Fields.idr:25`). (read, d79f9df7)
- Not done at HEAD: no module of the translation imports `Place`
  (measured: `git grep -n 'import IdrisMLIR.Frontend.Translate.Place'`
  finds the four growth modules only), so the translation threads no place
  and no keyed argument is computed from its site's term; no copy of
  `Host.putIn` is in `Translate/` (measured: `git grep -n putIn --
  compiler/src/IdrisMLIR/Frontend/Translate` finds none).
- The run-time re-check C257 deletes stands:
  `compiler/src/IdrisMLIR/Frontend/Finite.idr:171-172` (`unsound`, an
  internal error), `:180-185` (`heightWithin`), `:190-197` (`sizedWithin`),
  called at `:215-216`, `Translate/Types.idr:606` and `:905`. (read)
- D128's walk is not in yet: the translation still settles through the
  host's normaliser, `Translate/Closed.idr:413-414` (`lambdasApplied` over
  `host.normaliseHoles`), read by `Closed.idr:993` and by the growth model
  at `Growth/Sites.idr:1915` and `Growth/Template.idr:2422`. (read;
  `Terms.idr`'s uncommitted diff removes one `lambdasApplied` use)
- Owner L16. Remaining: the translation threads `Place` down the tree
  beside its term in the walk the growth model's sites use, binding a
  settled implementation's arguments once as `Sites.applyHead` does
  (D128); each keyed argument is computed from its site's term with
  `Host.putIn`'s run-time copy equal by `Refl`; then `Finite.unsound`,
  `heightWithin`, `sizedWithin` and their three call sites are deleted.

### C258, an instance's link keyed by its holes — Missing, in flight (L16ee)

- `Translate/Keys.idr:1104-1125`: the link is
  `MkLink head (map (map snd) arguments)`, each argument the
  `writtenOf` of `term x`, and `Translate/Instances.idr:193` passes
  `term = (.form)`, the static reading's form; the cache is looked up by
  that link (`lookupFact (.named) link`, `Keys.idr:1126`). (read)
- The holes travel beside it, not in it: `Instances.idr:111`
  (`FromDictionary (Maybe Holes) FixedDictionary`), `:122`
  (`AsDictionary holes`), `:656` (`MkHoles tys (MkBinder Many held)`). So
  two requests that differ only in their holes are still one link and
  share the first's `SignedAt`, the case C258's sharpening found. (read)
- The model side exists (`Growth/Sites.idr:415` `holedAt`), but the one
  hole-key function both reach through C257's walk does not. (read)
- Owner L16. Remaining (with C257's walk, as the sharpening orders):
  write the holes in the callee's telescope into the link's argument
  wherever the form does not fix them, computed by one function the
  translation and `Sites` both call; count held positions in the universe
  heights.

### C262, no cast follows a call — Partial

- Done in the dialect: `lib/IR/Func/Verifier.cpp:130-145`
  (`resultAxesFit`, refusing a static axis of a bare or graded array
  result), called from `FuncOp::verify` at `:196-201` before the extents;
  `lib/IR/OpsArrayShapes.cpp:87` (`tie_shape` answers `Carry::Free`).
  (read)
- Done in the C++ signature makers: `include/idr/IR/Func.h:269-283`
  (`returnable`, `returnedAs`), used by
  `lib/Transforms/Specialize/Consumer.cpp:129,162` and the raise's
  `Redirect.cpp:110-135` (`giveAs`, casting after the call only to a
  non-return use); copies keep their own extents
  (`lib/IR/Func/Extents.cpp:209`, `Columns/Calls.cpp:138`,
  `Tail/Outline.cpp:246`). (read)
- Done in Emit: `compiler/src/IdrisMLIR/Emit/Bodies.idr:563-590` (a call's
  result at `returned`, so a tail call is never cast; a non-tail slot
  Idris types statically casts after it), and constant result extents in
  `Emit/Declarations.idr:40-96`. (read)
- Not done (L16dv's sharpening, "an axis nothing states computed from the
  index terms the call is given"): `Emit/Tensors.idr:618-622`, the tie
  reads each dynamic axis neither stated nor fixed by `tied` off the array
  with `sizeAt` (`:118`, a `tensor.dim` of the call's result), emitted
  after the call and before the tie; its doc (`:600-605`) says "else read
  from it". Where a tie states one axis and not another, an op other than
  the tie then stands between a call and its tail, and `passesOn`
  (`lib/IR/Tail.cpp:41-50`) reads the call as no tail, silently. (read)
- Owner L16. Remaining: in `Emit.Tensors.tie`, compute an unstated
  dynamic axis from the call's index terms before the call (or leave the
  axis out of the tie), so nothing but the tie follows a call; delete the
  `sizeAt` read of the result and the doc's "else read from it".

### C262's data form — Open-owner

§4's one open question (`proposals/0000-mlir-native.md:5183-5221`): a
data result's layout at a tail call (A, B*, D2, C; B* recommended). At
HEAD a re-packing `data.reindex` after a tail call answers `Carry::Works`
(`lib/IR/Families/Refinement.cpp:96`), so the call is read as no tail and
`verify(FuncOp)` passes, as §4 states. Nothing for a lane until it is
ruled; the verifier check "lands first whatever is chosen". (read)

### C256, a request carries what it was keyed from — Partial, in flight (L16ee)

- Done: `WholeKind`, `NeededCut`, `HeldAs` in
  `Translate/Readings.idr:1775-1810`; the cut lemmas beside
  `Closed.cutShape` (`Translate/Closed.idr:1258-1284`); `TS` holds
  `0 growth : GrowthModel` (`Translate/State.idr:1523-1527`); the
  dictionary's reduct kept (`Closed.idr:1069` `FixedNow FixedValue`,
  `Cases.idr:498` `WholeParameter FixedValue`); the cache keeps and
  returns `SignedAt` (`Instances.idr:813-823`, `State.idr:540-543`). (read)
- Not done: `State.Request` (`State.idr:582-594`) holds `0 keys` and
  `0 atKey` but no per-position site membership and no `HeldAs`; `NoKey`
  (`State.idr:519`, `{0 k : PKind} -> AtKey Nothing k`) carries no
  evidence that its kind keys nothing. (read)
- Owner L16. Remaining: give `Request`, at quantity 0 per keyed position,
  the site's membership in `TS.growth`'s site table and its `HeldAs`, read
  where C257's walk finds the site; make `NoKey` take evidence that its
  `PKind` keys nothing.

### C228, the core term carries what Emit reads — Partial

- Done: a call holds its callee's signature and arguments
  (`compiler/src/IdrisMLIR/Term.idr:1422`), an axis is a `Fin` of the
  rank (`Term.idr:406`), a literal case keyed by one kind
  (`Term.idr:277-282`, `LitMatch`); Emit has no `internal` call (measured:
  `git grep -n -iE 'internal|assert_total|believe_me' --
  compiler/src/IdrisMLIR/Emit` finds none). (read, measured)
- Not done: Emit still checks one fact, `Emit/Tensors.idr:157-192`
  (`fitting`'s `Mismatch`, raised as `Unfit` and reported as an internal
  error at `Frontend/Program.idr:83-85`), kept because "a term is not
  indexed by its type". The translation re-derives three of the types
  C228 names behind internal errors: `Translate/Terms.idr:736` (a
  lambda's result type), `:746` (a forced value's type, marked "Kept"),
  `:1527` (an application's function type). (read; `Terms.idr` in flight)
- Owner L16. Remaining: carry the slot's type in the term so a value and
  its slot agree by construction (then delete `Mismatch`, `Unfit`,
  `EmitFailed`), and carry a lambda's result, a suspension's held type
  and an applied value's function type where the translation builds them,
  deleting the three internal errors.

### C153, the e-graph's form as D123 amended it — Partial, in flight (2b-S, L14x)

- The engine is D123's: rounds with a rebuild after each, union-find,
  outermost reach per class, a spent budget refuses nothing
  (`include/idr/Transforms/EGraph/Engine.h:33-69,98`, HEAD's text). (read)
- The pass's description still says "Rules from the specification
  applied at insertion" (`spec/Pipeline/Pipeline.idr:293`), the form D123
  replaced. (read)
- Owner L03. Remaining: rewrite `Pipeline.idr:292-293` to say rules run in
  rounds with a rebuild restoring congruence after each, and delete
  "applied at insertion".

### C156, the e-graph's nodes per op measured — Partial (stage 1)

- `spec/Pipeline/Pipeline.idr:296-303`: `nodesPerOp = 64`, "Not yet
  measured"; unchanged since recheck 3. (read)
- Owner L03, L14 measuring. Remaining: measure nodes made per op on the
  stage-1 module and replace 64 and its "not yet measured" with that
  figure, its build and its input.

### C178, program-sized state in the footprint containers — Partial (moved)

- Every site recheck 3 named now uses footprint containers
  (`Effects/Writer.cpp:87-88`, `InPlace/Unique.cpp:230-282`,
  `UniqueResults.cpp:63-65`, `Expect/LabelsLeast.cpp:123-127`,
  `StructureLoops/Linalg.cpp:44`, `Specialize/Order.cpp:187-188`,
  `Optimize/Settle.cpp:256`, `Optimize/Captures.cpp:80`,
  `Optimize/CaptureDrops.cpp:163`, `Deduplicate/Deduplicate.cpp:156-157`,
  `Defunctionalize/Declare.cpp:112`). (read)
- Two program-sized solver indexes are still plain `llvm::DenseMap`:
  `include/idr/Analysis/Solver/TypeGraph.h:91` (`index`, beside a
  `footprint::Vector` of the same nodes) and
  `include/idr/Analysis/Ownership/ExclusivityDetail.h:121` (`keys`).
  (measured: `git grep -nE '(llvm::)?DenseMap<' -- foreign/idr/lib
  foreign/idr/include | grep -v footprint::DenseMap | grep -v Generated`,
  30 hits, the rest lowering, driver, cold diagnostics or content-keyed)
- Owners L14 (`TypeGraph.h`), L08 (`ExclusivityDetail.h`). Remaining:
  make both `footprint::DenseMap`, so each pass's footprint counts them.

### C205 and C218's first settlement, as D127 amended them — Partial, in flight (L14x)

- HEAD's committed `include/idr/Transforms/EGraph/Engine.h:14-22,205-217`:
  an integer is an `APInt` off the class's range and "any other constant
  is one an op of the input holds", which is C205 and C218 before D127; a
  string, a `Double` or a big is not computed in the graph. (read via
  `git show HEAD:`)
- C205's own part holds: no attribute is made in the graph, and C198's
  never-folded ops are a generated list checked when the compiler is built
  (`lib/Transforms/EGraph/Rules.cpp:70`, `static_assert(noneComputed(
  generated::NeverFolded{}))`). D127's work is uncommitted (`Fold.h`,
  `EGraph/*`, the untracked `EGraph/Values.cpp`). (read, `git status`)
- Owner L14, with L13 for `include/idr/IR/Fold.h`. Remaining: give the
  graph strings, Doubles and bigs as value domains computed by the
  runtime's functions through `Fold.h`'s conversions made generic over the
  domain, the attribute made only at write-back; rewrite `Engine.h:14-22`.
  C218's second settlement (`idr.refusal` bare) is done.

### C213 and C217, refused only where a set is unbounded — Partial, unmoved, in flight (L16ee)

- HEAD's `Translate/Terms.idr:612-615` refuses `RuntimeClosure` with "a
  function computed at run time, applied inside a settled term that
  settles it again", and `:1002-1006` with "a form whose type its body
  does not give, applied inside a settled term"; neither names a member
  or use-type set no analysis bounds. (read via `git show HEAD:`)
- Owner L16. Remaining: under D128 (the settled implementation walked as
  written, its arguments bound once), compile the two situations; any
  refusal left names the unbounded member or use-type set and its site.

### C222, requests and sites one table — Partial, in flight (L16ee)

- `Translate/State.idr:1523-1527` (TS holds `0 growth : GrowthModel`);
  `Request` (`State.idr:582-594`) holds no site membership; the run-time
  re-check stands (`Frontend/Finite.idr:171-216`,
  `Translate/Types.idr:606,905`). (read)
- Owner L16. Remaining: as C256 and C257 above; it closes with them.

### C201, the tools' stacks and the outside-code margin measured — Partial (stage 1)

- `CMakeLists.txt:262,279,297,330`: every target entry still calls
  `idris_mlir_unmeasured_stacks()`; `:216-223` refuses to configure
  without the three sizes. Unmoved since recheck 3. (read)
- Owner INT, L11 measuring. Remaining: measure
  `IDRIS_MLIR_TOOL_STACK_BYTES`, `_TOOL_SIGNAL_BYTES` and
  `_OUTSIDE_STACK_BYTES` per target, record each in its entry with its
  build and input, and delete that entry's
  `idris_mlir_unmeasured_stacks()` call.

## Superseded

- **C149, C163** — by C165: patch 78 is not applied; its submission files
  stay (`upstream/78-func-to-llvm-expanded-arg-attrs/`), and
  `upstream/README.md:143` says "not carried since 2026-10-21 (C165)".
  (read, `ls`)
- **C185** — its claim level by D122, carried out:
  `lib/Transforms/Bufferize/Releases.cpp:59` (`bufferClaim =
  idr::Unique::Self`); `lib/Transforms/InPlace/Rule.cpp:124-138`
  (`boundaryAsks` reads `HoldsBuffer` only for when the promise binds, as
  D122's correction says). The rest stands as C188 amended it. (read)
- **C225** — by D113 the same day, then D119 and C237: the parser has no
  `assert_total` or `assert_smaller` (measured: `git grep -n
  'assert_total\|assert_smaller' -- compiler/checker/src/Idris/Parser.idr
  compiler/checker/src/Libraries/Text compiler/checker/src/Parser` finds
  none).
- **C230, C232** — withdrawn by D116: the language is not widened for the
  checker's code; nothing in the tree to check.
- **C212** — withdrawn 2026-10-22, carried out:
  `compiler/checker/src/Core/Termination/SizeChange.idr:447,451` (`allFins`
  once per graph); `libs/mlir-array` has no `Nat`-indexed read (measured:
  `git grep -i 'readNat|indexNat|NatIndex' -- libs/mlir-array` finds 0).

## Done

C131 to C185:

- **C131** `harness/Facts.idr:53-78` (expected ending read as
  `Spec.Ending`), `harness/Reject.idr:39-42` (`{rule; line; message}`);
  no `run.sh`/`e2e.sh`/`differential.sh` remains (measured: `git ls-files
  | grep -E '(run|e2e|differential|actions|lit|profile)\.sh$'` finds only
  `bench/run.sh`).
- **C132** `harness/Universal.idr:127-147` (drawn skip set, seed printed),
  `harness/Programs.idr:380` (`--emitted`); `tests/actions-skip-programs`
  gone. (read, `ls`)
- **C133** nine `tests/scale-*` fixtures, `scale-threads` among them;
  relation at `harness/Scale.idr:661-668`; `defunc-tag-limit` gone. (read,
  `ls`)
- **C134** as amended by C197: `harness/harness.ipkg:7-9` depends on
  `idris-mlir-spec` alone; no `system`, `Test.Golden` or `Language.JSON`.
  (read, measured)
- **C135** `harness/Lit.idr:388-450` (`%differential` with stdin
  inputs); `maxCases` gone. (read, measured)
- **C136** a placement in §7, no code. (read)
- **C137** `tools/idris-mlir-tblgen.cpp:21` (`-gen-admitted-classes`);
  `include/idr/IR/Generated/AdmittedClasses.h.inc`, `BigToWord.h.inc`.
  (read)
- **C138, C177** `runtime/Alloc/Peaks.cpp:43` ends `FrameBoundExceeded`,
  in `spec/Runtime/Endings.idr:155,176`; `runtime/check-archive.sh:96`;
  `tests/runtime-frame-bound`. (read)
- **C139** one `decide`, `lib/IR/Tail.cpp:121-127`, verified at
  `:162-215`; in flight (2b-T, which committed 16ac96c4 during the read
  without changing the decider). (read)
- **C140** as D93 amended it: `spec/Lifetimes/Kind.idr` (`View | Room |
  Cursor | Home Nat`), `lifetime.forget` at
  `spec/Lifetimes/Declarations.idr:652`; no op carries
  `AutomaticAllocationScope`. (read, measured)
- **C141** fixed upstream, no patch carried (`ls upstream`). (measured)
- **C142** `proposals/0011-data-oriented-frontend.md:8,457`,
  `0017-apple-dmp.md:5-13`, `0018-fin-words.md:5-8`. (read)
- **C143** `include/idr/IR/Grades.h:133-146`;
  `spec/Grades/Declarations.idr:9-12`. (read)
- **C144** moved since recheck 3: no `Undecided`, `HoldsUndecided`,
  `StageHolds` or `holdsAt` remains (measured: `git grep`; removed by
  276351d4); `uncounted` reads `countingAt`
  (`lib/IR/OpsArrayFusion.cpp:130-132`). (read)
- **C145** `spec/Lifetimes/Declarations.idr:583,596-600`. (read)
- **C146** `spec/Lifetimes/Declarations.idr:665` (`reserve`: cursor to
  room). (read)
- **C147** one `Cursor` kind; `OnStack`, `InChain` openers at
  `spec/Lifetimes/Declarations.idr:60-100`. (read)
- **C148** `Home Nat` in `spec/Lifetimes/Kind.idr`. (read)
- **C150** `compiler/src/IdrisMLIR/Term.idr:417` (`ReadBack`),
  `Emit/Bodies.idr:874-892` (the array given back). (read)
- **C151** a measurement record, no code. (read)
- **C152** `spec/Arrays/Memory.idr:98-113`; ODS `MemRead<Idr_ContentsResource>`
  at `include/idr/IR/Generated/IdrOps.td:893`. (read)
- **C154** no library body builds a `Dec` (measured: `git grep -nE ':
  .*\bDec\b' -- libs` finds none).
- **C155** no synthesizer in the tree; the laws at
  `spec/Ops/Numeric.idr:146-158`, checked by `Numeric/Laws.h`. (read,
  measured)
- **C157** no `applyPatterns*Greedily`, `getCanonicalizationPatterns`,
  `hasCanonicalizer` or canonicalizer pass under `foreign/idr` or
  `compiler/spec` (measured).
- **C158** moved since recheck 3: `spec/Ops/Values.idr:7` now says
  `idr.platform.os`; the bare mnemonics are the ruled and structural ones
  plus `carrier` (D124). (read, measured)
- **C159** `lib/IR/Func/Values.cpp:104-107` (`admitsWrite`: counted and
  `Unique::Self`). (read)
- **C160** `spec/Lifetimes/Declarations.idr:647-665`. (read)
- **C161** `include/idr/IR/Generated/IdrOps.td:2494-2520` (`count.dup`,
  `count.drop` take `isCountedValue`). (read)
- **C162** `lib/IR/Grades.cpp:161`. (read)
- **C164** `tests/spec-current/run:4-19`; `generated.manifest`. (read)
- **C165** see C149 above. (read)
- **C166** `spec/Control/Matches.idr:237-242`; `lib/Analysis/Ranges.cpp:96`
  (`excluding`). (read)
- **C167, C176** `lib/IR/Tail/Destinations.cpp:32-43`. (read)
- **C168** `runtime/idris_rt.h:323-327`. (read)
- **C169** `runtime/Strings/Simd.h` (final class, `static_assert`, no
  run-time selection). (read)
- **C170, C181, C182** `outers` and `StatesOuters` on `data.field`,
  `data.con`, `data.reindex`, `lin.cast`, `data.match`, `lit.match`,
  `join`, `loop` (`spec/Families/Ops.idr:103,151,232`,
  `spec/Grades/Declarations.idr:277`); checked at
  `lib/IR/Lifetimes/Verify.cpp:235-265`. (read)
- **C171, C179** `spec/Tail/Declarations.idr:143-165` (`dest.answer`,
  variadic results and outers, one region). (read)
- **C172** `tools/bootstrap.sh:64-65,729`. (read)
- **C173** `raiseClaims` at `lib/Transforms/InPlace/UniqueResults.cpp:347`,
  `InPlace/Writer.cpp:165`; in-place and unique-results before bufferize
  (`spec/Pipeline/Pipeline.idr:230,316,325`). (read)
- **C174** `Translate/Choices.idr:13`, `Translate/State.idr:708` (the
  closed sum of implementations); its refusals are C213's and C217's
  rows. (read)
- **C175** `compiler/src/IdrisMLIR/Frontend/Finite.idr:23-32`. (read)
- **C180** `spec/Arrays/Memory.idr:334` (`array.place_copy`),
  `lib/Transforms/Bufferize/Bufferize.cpp:215`, `Emit/Tensors.idr:4-9`.
  (read)
- **C183** `compiler/checker/src/Core/TT/Stored.idr`,
  `Core/Context.idr:732-744`. (read)
- **C184** no header beside a `.cpp` (measured: `git ls-files
  foreign/idr/lib | grep -E '\.(h|hpp|inc)$'` finds 0).

C186 to C224 (C205, C213, C217, C218, C222 and C201 above):

- **C186** `runtime/Alloc/Peaks.cpp:4-14` (entries empty in the shipped
  runtime); `tests/shipped-accounts`. (read, `ls`)
- **C187** `upstream/99-function-interface-edits/`, `PINS.md:1110-1128`,
  `tests/upstream-function-interface-edits`; `lib/IR/Func/Edits.cpp:188-212`.
  (read)
- **C188** no sharing claim written by the frontend (measured: `git grep
  -i 'unique self|unique deep'` over `Emit` and `Translate` finds 0);
  `lib/Transforms/InPlace/Rule.cpp:124-138,276`. (read)
- **C189** `lib/Transforms/Tail/Frames.cpp:23-30`, `Lifetimes/Pass.cpp:55`
  (both in flight, 2b-T), `Lifetimes/Decide.cpp:45`. (read)
- **C190** one `raiseClaims`, `lib/Transforms/InPlace/Writer.cpp:165`,
  `UniqueResults.cpp:347`. (read)
- **C191** `include/idr/Transforms/EGraph/Engine.h:16-19` (HEAD: a built
  node's interval from its kind's generated range function, no op made);
  in flight. (read)
- **C192** moved since recheck 3: `spec/Counting/Declarations.idr:447`
  (`own.adopt` legal `between First Owned`), `:423-437`; no `ownAdoptOp`
  under `compiler/src` (measured); in flight (spec). (read)
- **C193** `compiler/src/IdrisMLIR/Registry/Recognized.idr:139`,
  `Registry/Faster.idr:85-87`. The claim question it left is D122's. (read)
- **C194** `spec/Closures/Memo.idr:129,163`;
  `lib/Transforms/StructureLoops/JoinLoops.cpp:4,34`, `Updates.cpp:3`.
  (read)
- **C195** no `Exclusive` handle (`lib/Transforms/Ownership/Exclusive.cpp:137`
  is the pass); `include/idr/IR/Quantities.h:44-117` (`Token`, branch,
  rejoin). (read)
- **C196** `spec/Ops/Platform.idr:226-255`;
  `lib/Transforms/Counting/Borrows.cpp:26`. (read)
- **C197** with its sharpening and shape, moved since recheck 3:
  `spec/Core/Op.idr:298` (`GuardKind`), `spec/Ops/Checks.idr:338-344`
  (`guardOpOf`), `harness/Prims.idr:418-436` (a total match, no lookup, no
  `Left`). (read)
- **C198** `spec/Core/Admitted.idr:55` (`UpFold = UpstreamFold |
  NeverFolded`), the nine ops in `spec/Ops/Shapes.idr`. (read, measured)
- **C199** as amended: `Makefile:371-373` (`knowngen check`); no manifest
  entry. (read)
- **C200** `include/idr/Support/Match.h:224-225` (`static_assert(eachNamed,
  ...)`). (read)
- **C202** moved since recheck 3: `include/idr/Analysis/Ownership/Walks.h:43-53`
  (`followed` shuts out `upstreamElement`, `Ownership/Facts.h:325-328`),
  so `writeVersion` (`Ownership/Exclusive.cpp:77-91`) never re-grades it;
  `InPlace/Chains.cpp:180-183`. (read)
- **C203** `Emit/Bodies.idr:563-590` (every call `NonTail`). (read)
- **C204** no `index_switch` under `compiler/src` (measured);
  `lib/Conversion/Matches.cpp:146-186`. (read)
- **C206** moved, completed by C244: `lib/IR/Tail.cpp:30-33`,
  `lib/IR/Families/Refinement.cpp:96`. (read)
- **C207** `lib/Transforms/StructureLoops/Updates.cpp:3`. (read)
- **C208** `lib/Transforms/Counting/Placement.cpp:221-238`. (read)
- **C209** `lib/IR/Verify/Linearity.cpp:391`,
  `include/idr/IR/FlowEdges.h:203-250` (`partOf`). (read)
- **C210** `lib/Driver/Main.cpp:95` (`--disable-fp-call-folding` last).
  (read)
- **C211** `lib/Analysis/Ranges.cpp:83-96`. (read)
- **C214** `lib/Conversion/Lower/Destinations.cpp:31-43`;
  `lib/IR/Layout/Components.cpp:243-246` (in flight). (read)
- **C215** `lib/Conversion/Lower.cpp:135-140,189-192`;
  `lib/Analysis/Constants.cpp:36`. (read)
- **C216** `compiler/checker/src/Idris/Syntax/Tree.idr:1-14`. (read)
- **C219** as sharpened, moved: `Translate/State.idr:956` (`Holding =
  AMember | NoMember | ByInstance`), both readers through
  `Boundary.choiceHolding`; in flight. A one-line wrapper is written
  twice, `Growth/Sites.idr:1207-1208` (`holdingOf`) and
  `Translate/Types.idr:432-433` (`typeHolding`), queued at 9f4b74b9.
  (read)
- **C220** `Translate/Boundary.idr:272-288`. (read)
- **C221** moved: `Translate/Contraction.idr:5-6,291-296` (`EtaNormal`
  with `Proof.Reading.EtaContracts`'s evidence). (read)
- **C223** moved: `Growth/Graph.idr:1737-1778` (`heldCount` from the
  program), its two facts stated in `Proof/Held.idr:12,93-101`; in
  flight. (read)
- **C224** as sharpened, moved: `Growth/Graph.idr:15-22` (a holder's
  one-value and many-value positions); in flight. (read)

C225 to C263:

- **C226** as D115 and D120 amended it: `foreign/idr/CMakeLists.txt:36-45`
  takes `NDEBUG` out of our units and refuses an LLVM without assertions
  outside the typecheck build; `tools/bootstrap.sh:926`
  (`-DLLVM_ENABLE_ASSERTIONS=ON`); the runtime keeps `NDEBUG`
  (`runtime/CMakeLists.txt:172`); no contract syntax yet, as clang has
  none. (read, measured)
- **C227** `Growth/Template.idr:35-39` (HEAD's text: a lambda chain around
  a stuck call read as both forms, `SEta`; `believe_me` read beside the
  value it gives back); in flight (L16ee). (read)
- **C229** the dialect modules are checked by `tests/dialects-current`
  (suite `test-mlir-tools`, `tools/dialects.sh check`) and take no
  manifest entry (measured: `grep -n 'Syntax/' foreign/idr/generated.manifest`
  finds none); no Python file under `tools/` (measured: `git ls-files
  tools | grep -c '\.py$'` is 0).
- **C231** as sharpened and corrected: an instance's binder admitted once,
  at the request, refusing `value type` there
  (`Translate/Instances.idr:433-449`), `classifyAt` taking `Admitted`
  (`:459-461`); `staticsOver` keeps `PastBinders`
  (`Growth/Implementations.idr:153`); the registry's validated row refused
  once (`Translate/Boundary.idr:1176`, `Frontend/Resolve.idr:163,308`).
  (read)
- **C233** `compiler/checker` with package `idris-mlir-checker`;
  `compiler/idris`, `tools/extract-idris.sh`, `MODULES` and every
  `upstream/fork-*` gone; AGENTS.md has no import fence (measured: `ls`,
  `git grep -n 'compiler/idris/'` finds no live reference outside audits
  and proposals).
- **C234** as corrected: the signature read once at the request and
  cached (`Translate/Instances.idr:806-823`, `State.idr:540-543,582-594`).
  (read)
- **C235** `include/idr/Support/Match.h:186-243` (`foldTypes`,
  `matchTypes` over `DialectTypes`, generated from `IdrTypes.cpp.inc`,
  `include/idr/IR/IdrDialect.h:99-107`); `foldDialect` gone (measured).
  Its header's sentence that a type interface "is not used to say what
  each of our types is" (`Match.h:8-12`, L15) now reads against D126's
  type interfaces (bb8ce09c); a comment, not the mechanism. (read)
- **C236** §5.2 corrected (`proposals/0000-mlir-native.md:5494-5497`); the
  solver's handle tables are its boundary: `Analysis/Solver/Extraction.h:88-135`
  (a `Numbering` whose map goes at `finish`), `LabelPoints.h:3-10` ("the
  solve between reads numbers alone"). (read)
- **C237** `compiler/checker/src/Libraries/Text/Parser/Core.idr:23-29,151-156`
  (an erased bound, a box, one fixpoint); `Idris/Parser.idr:24`
  `%default total`. (read)
- **C238** `include/idr/Analysis/Solver/Schedule.h:4-17,77-81` (waves on
  `parallelForEach`, no atomics); `tests/mlir-layout/expected:4`,
  `run:10,44` (the per-thread ledger admitted). (read)
- **C239** as amended: `lib/IR/Func/Verifier.cpp:147-185` (`extentsFit`);
  the frontend writes extents (`Emit/Declarations.idr:40-96`) and
  `extentDim` is gone (measured); the substitution maps extents and makes
  an input axis static (`lib/IR/Families/Substitute.cpp:177-209`), its one
  walk re-inferring through `InferTypeOpInterface` with a cast back where
  a use's type is fixed (`:306-345`). D124 has since ruled the lending
  question the graded limit waited on; no decision revisits that limit.
  (read)
- **C240** as C261 amended it: Emit writes `idr.join`/`idr.loop`
  (`Emit/Bodies.idr:4-5,461-470`); `lib/Transforms/Optimize/Contify.cpp:6`
  ("promises nothing"). (read)
- **C241** as sharpened: `include/idr/IR/Func.h:263` (`staticSizeAt`),
  `:299-310` (`meets`), read by `lib/IR/Func/Call.cpp:242` and closure
  constants `lib/IR/Constants.cpp:107`; `holdFits` at
  `include/idr/IR/Grades.h:190`. (read)
- **C242** `Translate/State.idr:86-97` (`StaticReading` holding its
  `0 reading`), `Growth/Template.idr:2698-2712` (`staticReading` cached by
  kind and written key); `ArgumentFrom` at
  `compiler/src/IdrisMLIR/Proof/Covers.idr:1249`. (read)
- **C243** §5.2 (`proposals/0000-mlir-native.md:5490-5492`). (read)
- **C244** `spec/Tail/Declarations.idr:180-218` (`Carry`,
  `CarriesOnOpInterface`); `include/idr/IR/Traits.h:78-87`
  (`ResultCarriesOperand` answers `Free`); `lib/IR/Families/Refinement.cpp:96`;
  readers through `tail::carriesOn` (`lib/IR/Tail.cpp:30-33`,
  `Tail/Context.cpp:190,260`, `TrmcRewrite.cpp:30`,
  `AccumulatorPlan.cpp:267`); no `dyn_cast<DataReindexOp>` (measured).
  `Tail.cpp` in flight (2b-T). (read)
- **C245** `tools/bootstrap.sh:1667-1680` (`flock`), `tools/host.sh:120-150`
  (`wait4`). (read)
- **C246** no `.awk` under `tests/` and `harness/lib/harness.sh` is 283
  lines of glue that starts tools or hands words to the runner
  (`:3-8,155-202`) (measured: `git ls-files 'tests/*.awk'`, `wc -l`).
- **C247** `spec/Core/Interfaces.idr:106-110`; implemented by `data.con`
  (`lib/IR/OpsCon.cpp:40`), `nat.pred`, `big.add`
  (`lib/IR/OpsBigs.cpp:237,244`); asked at
  `lib/Analysis/IdentitiesRecord.cpp:188-190`. (read)
- **C248** IO tail runs read by `tailHead`'s `RunHead`
  (`compiler/src/IdrisMLIR/Term.idr:1421-1431`, through ties); `tie_shape`
  answers `Free` (`lib/IR/OpsArrayShapes.cpp:87`); no `data All` in
  `compiler/src` (measured), base's imported
  (`Emit/Bodies.idr:33`). (read)
- **C249** as amended and sharpened: `Definitions`, `Literals` import no
  translation module, `Contraction` imports `Definitions`, `Readings`
  those three, `State` imports `Definitions` and `Readings` and nothing
  above (measured: the imports of each); `kindsOf` gives a `Vect` of the
  applied arity (`Translate/State.idr:596-604`). (read)
- **C250** as corrected: `lib/Conversion/Elements.cpp:109-110`
  (`unique self` claim, no test), `:122-134` (the one run-time test kept
  with its reason). (read)
- **C251** a counting rule for §6's check; nothing in the tree to carry.
  (read)
- **C252** `spec/Closures/Declarations.idr:97-106,410`;
  `lib/IR/Constants.cpp:62-76` (the callee binds no index variable).
  (read)
- **C253** no `!idr.token` or our own `TokenType` remains outside
  generated files (measured: `git grep -n '!idr\.token\b\|\bTokenType\b'`
  finds upstream's builtin token only); `ReuseTokenType` in 13 units
  (measured).
- **C254** `Growth/Graph.idr:37,206-217` (HEAD's text: positions numbered
  first, `LandingTable` by number); `DropsReach`, `thenNothing` gone
  (measured, 9704182a); in flight (L16ee). (read)
- **C255** `Translate/State.idr:1081-1084,1107,1277-1278` (`Defined =
  DefinitionRead Nature`, `Read = Reading Nature`, a nested block's name
  only where a walk names it). (read)
- **C259** `DictParam` holds a `FixedDictionary`
  (`Translate/State.idr:206-207`, keyed at `:514-515`), `Cases.idr:498` (`WholeParameter
  FixedValue`); no whole-parameter internal error in `Cases.idr`
  (measured: its one `internal` is `:953`, another check). (read)
- **C260** `Translate/State.idr:1204,1217,1270-1271` (`SolvedAs`,
  `solutions`, `pair`); `Boundary.idr:973,1143-1159` (filled after the
  freeze); `Closed.idr` has no `internal` (measured). (read)
- **C261** as sharpened: `callsOf` (`Term.idr:1482-1489`) feeds
  `jumpedBy` and `fitsRuns` as set membership
  (`Translate/Programs.idr:466-523`, every run region read), and
  `joinsIn` (`Term.idr:1915-1966`) rewrites once, total; no `throughAll`,
  no `internal` in `Programs.idr` (measured). (read)
- **C263** `Translate/Instances.idr:285-295` (a universe-valued binder a
  type parameter at any quantity), the type case by the known type's head
  in `Cases.idr` (4dfbe945), with `tests/type-case-heads`,
  `type-case-partial`, `type-parameter-quantity-many`; in flight (L16ee).
  (read)

## Count

133 decisions (C131 to C263), each read with its amendments:

| | C131-C185 | C186-C224 | C225-C263 | all |
|---|---|---|---|---|
| Done | 49 | 32 | 31 | 112 |
| Partial | 3 | 6 | 4 | 13 |
| Missing | 0 | 0 | 1 | 1 |
| Regressed | 0 | 0 | 0 | 0 |
| Superseded | 3 | 1 | 3 | 7 |

One further item is Open-owner: C262's data form, §4's open question.
C218 counts as Partial (its first settlement; the second is done).

- Partial: C153, C156, C178, C201, C205, C213, C217, C218, C222, C228,
  C256, C257, C262.
- Missing: C258.
- Superseded: C149, C163 (by C165), C185 (claim level, D122), C212
  (withdrawn), C225 (D113), C230, C232 (D116).
- Need stage 1 (a measurement, no code): C156, C201.
- In flight: C153, C205, C213, C217, C218, C222, C256, C257, C258, and
  the Done rows so marked.
- Moved since recheck 3: C144, C158, C178 (in part), C192, C197, C202,
  C206, C219, C221, C223, C224.

## Seen outside the range

- `lib/Analysis/Constants.cpp:36` (L14) builds `sortedIds(NeverFolded{})`
  at run time from a generated static list, once per run.
- `compiler/src/IdrisMLIR/MLIR.idr:149` (L16): `typeText TokenType =
  "none"` with "this is never read", a wrong text kept for a state the
  type still allows.
- `compiler/src/IdrisMLIR/Frontend/Finite.idr:224` (L16): an internal
  error for "an instance requested again as new on its own chain", a
  fact the request's construction could carry (D112).
