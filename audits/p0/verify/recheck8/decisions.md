<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 8: decisions C131 to C303, rulings D132 and D133, against HEAD

HEAD at start b8a6177f7, at finish 0c05843ef (a queue-only commit). By
reading and `git grep … HEAD` over the committed tree; nothing was built,
generated or run, so DONE means done in the code, by reading. Paths are
under `foreign/idr/` unless they start with another top-level directory;
`Spec/` is `compiler/spec/IdrisMLIR/Spec/`, `Translate/` and `Growth/`
are under `compiler/src/IdrisMLIR/Frontend/`.

Method: C131-C279 start from recheck 6's verdicts
(`recheck6/decisions-C131-C279.md`, at d093dbfb). Every non-Done row was
re-read; every Done row's evidence was re-grepped at HEAD
(`/tmp/r8/c1.txt`, `/tmp/r8/scripts/chk.sh`), with the rows the cull and
rederivation units touched read again. C280-C303, D132 and D133 are
checked in full. Items the brief names as in flight (K10-K16, K17-K22,
C281 steps 2-6, C292, C293, C294, C299, C302, D133 steps 3-8, and the
dispatches of the queue's last section) are IN FLIGHT, not re-traced.
C273 and C274 were never recorded.

## Counts (171 decisions and 2 rulings)

| | C131-C185 | C186-C224 | C225-C263 | C264-C279 | C280-C303 | D132-D133 | all |
|---|---|---|---|---|---|---|---|
| DONE | 47 | 34 | 26 | 11 | 10 | 1 | 129 |
| PARTIAL | 1 | 3 | 3 | 0 | 1 | 0 | 8 |
| OPEN | 0 | 0 | 1 | 1 | 1 | 0 | 3 |
| IN FLIGHT | 0 | 1 | 2 | 1 | 11 | 1 | 16 |
| NO CODE | 4 | 0 | 3 | 0 | 1 | 0 | 8 |
| SUPERSEDED | 3 | 1 | 4 | 1 | 0 | 0 | 9 |

Moved since recheck 6: C272 Not done → DONE (bc08f0952); C279's lagging
sentence fixed (08c59751e); C275 Done → SUPERSEDED by C293; C246 Done →
PARTIAL (three stale comments); C222, C256, C257, C264 → IN FLIGHT
(C281's steps and C302 are running). No regression of a Done row.

## PARTIAL and OPEN, by owner

### L16 (`compiler/src`)

- **C258 — OPEN** (rides C281 steps 2-6, L16et). The link is still
  `MkLink head (map (map snd) arguments)` (`Translate/Keys.idr:1122`); the
  holes travel beside it (`Translate/Instances.idr:115, 126, 161`,
  `FromDictionary (Maybe Holes) …`), so two requests differing only in
  their holes are one link. Recipe: write the holes into the callee's
  telescope through `callIndices`' level map as a second component of
  the dictionary's written argument, read by one function
  (`Growth/Sites.idr:279`, `holedAt`).
- **C228 — PARTIAL.** Emit still checks one fact: `Emit/Tensors.idr:160-171`
  (`Fitting`'s `Mismatch`), `Emit/Monad.idr:55-74` (`Unfit`, `unfit`),
  `Emit.idr:65-76` (`EmitFailed`), reported as an internal error at
  `Frontend/Program.idr:83`. The translation re-derives two types as
  internal errors: `Translate/Terms.idr:745` (`forcedType`) and `:1588`
  (`applied`). Recipe: `Types.coreTypeIn` returns Core and Idris types
  together so the head and operand carry them, the slot's type rides the
  term, then delete `Mismatch`, `Unfit`, `EmitFailed` and the two
  internals. Waits: L16ey holds Emit; `Terms.idr` is under C281's fold.
- **C213, C217 — PARTIAL** (rides C281's fold). Four `RuntimeClosure`
  refusals name a translation situation over a set the program fixes:
  `Translate/Terms.idr:627` (a value a possibly-diverging definition
  computes inside a settled form), `:720` (a function where a fixed
  choice is expected), `:1142` (a value an implementation closes over,
  computed inside another), `Translate/Cases.idr:977` (a field no
  reduction reaches). bc08f0952 fixed the `formType` one. Recipe: compile
  each under D128's walk; a refusal left names the unbounded member or
  use-type set and its site.
- **C284 — PARTIAL.** Done: the specification's `ArrayMeaning`
  (`Spec/Arrays/Declarations.idr:343`, 239094524) and `tensor.concat`,
  `tensor.pad`, `tensor.yield` admitted for words (`:58`, 688f6b905).
  Not done: the frontend reads no `ArrayMeaning` (`Registry/Entry.idr:210-239`
  `ArrayPrim`, `Translate/Terms.idr:2355-2690` `arrayTerm`), and Emit
  joins word arrays slice by slice (`Emit/Tensors.idr:361-380`), not as
  `tensor.concat`/`tensor.pad`. Recipe: section6.md N10. Waits: L16ev
  (`Registry/{Entry,Recognized}`, `Resolve`).

### L12, L16, L18

- **C268 — OPEN** (and so **C262 — PARTIAL**, whose other parts stand:
  `lib/IR/Func/Verifier.cpp:130`, `OpsArrayShapes.cpp:87`,
  `IR/Func.h:252-277`). `tie_shape` still ties every dynamic axis in
  order (`Spec/Arrays/Memory.idr:414-418`; `OpsArrayShapes.cpp:76-78`
  refuses another count). Emit's `tie` reads an unstated axis off the
  array (`Emit/Tensors.idr:648-649` through `sizeAt`, `:116-118`).
  Recipe: L12 gives the op an attribute naming its tied axes with sizes
  for those alone, read by inference, reify and value bounds; L18's
  re-inference reads it; L16's `tie` states only stated axes and emits no
  tie where nothing is stated. Waits: L12ab holds `Spec/Arrays`.
- **C295 — OPEN** (L12, L16; O6 of the rederivation plan, its wait on
  L05y now met; not dispatched). `Bufferize/Releases.cpp:226-236` sets
  `writable` on `to_tensor` where a claim is raised; Emit casts a buffer
  field to the bare carrier before `to_tensor {restrict = True}`
  (`Emit/Bodies.idr:412-425`), forgetting its uses and claim. Recipe: an
  op that takes the cell opens its buffer as a tensor, so the claim
  reaches the opener; delete the flag write and the bare cast. Waits:
  L12ab (`Spec/Arrays`), L16ey (Emit).

### L19 (`tests/`)

- **C246 — PARTIAL.** `harness/lib/` holds `harness.sh` alone, but three
  run scripts still cite the deleted `lib/e2e.sh` as present:
  `tests/harness-cases/run:4`, `tests/harness-near/run:4`,
  `tests/semantics/run:9` (C251's stale sentence). Recipe: cite
  `harness/Programs.idr:278, 336` (`sem_case`, `near_neighbour`); the
  `e2e_cases` named exists nowhere.

### L03 and INT (stage 1, the owner's machine)

- **C156 — PARTIAL.** `Spec/Pipeline/Pipeline.idr:296-305`: `nodesPerOp =
  64`, "Not yet measured". Recipe: measure nodes per op on the stage-1
  module; record the figure, build and input.
- **C201 — PARTIAL.** `CMakeLists.txt:186` defines
  `idris_mlir_unmeasured_stacks()`, called by every target entry at
  `:231, 248, 266, 299`. Recipe: measure the tool stack, signal stack and
  outside-code margin per target, record each in its entry, delete the
  call.

## IN FLIGHT (not re-traced)

- **C222, C256, C257** (C281 steps 2-6, L16et): the site table is one
  (`State.idr:1888`, `Undrawn`), step 1's annotated tree landed
  (`Translate/Annotated.idr`, b2e9c4d21); `Request` still holds no
  `DrawnFrom`/`HeldAs`, and the run-time re-check stands (section6.md N7).
- **C264** ((a), (b) done; (c)'s call-argument half is C302, L14ad).
  (b)'s text was corrected by a27b66b41 and 762739168.
- **C281** (step 1 done, b2e9c4d21; steps 2-6 one change, L16et).
- **C283** (the fold's open points; carried out by C281 steps 3-6).
- **C288, C289** (how D133 is met; D133 steps 3-8, L17bh).
- **C291**: done for signatures (f392a02e4: results graded `once`, call
  results built once); dead-result elimination's rule for a linear
  result is L18ad's c291 `Results.cpp` patch with linear-kept's result
  half (dispatched).
- **C292** (after L16ey; its precondition test landed, e1a2d2b07,
  `tests/self-application-may-diverge`), **C293** (L18ac),
  **C294** (L10aa), **C302** (L14ad, uncommitted).
- **C297** (K22, after K16): `showError` stands (`checker/src/Core/Core.idr`,
  97 hits).
- **C299**: U04 landed the guard (675fd966d, `idr.check.byte`); the
  message following D64 is L13z's (with K10).
- **D133**: steps 1 and 2 landed (3d98cac27, 7aedeacb7). Left: six
  applications through `trusted = believe_me ()`
  (`checker/src/Idris/Host.idr:95-96`; uses `:901, 2781, 2792` (two),
  `:2866, 2917`), `host = assert_total (MkHost …)` (`:2983`), and the
  frontend's four escape hatches; no other `believe_me` of ours is
  applied (measured: every other hit is text, a spelling or a refusal).

## Decisions whose text the tree or a recorded plan contradicts

1. **The cull plan's amendments are not in the proposal.** `cull/plan.md`
   §3 says "the coordinator records each": C113 (`io.unsafe_run`), C146
   and C160 (`idr.lifetime.reserve`), C18, C34 and C15 are "amended", and
   rt 3 strikes "counts over runs of slots". None is recorded:
   `proposals/0000-mlir-native.md:4912-4916` (C146) and `:5053-5060` (C160)
   still decide that `reserve` exists, and K11 (in flight) deletes it;
   §5.5 still says "counts over runs of slots" (`:6349`) though K07
   deleted the run entries. The other §3 settlements (pipe 3, 4b, 7;
   dia 1; rt 2; fe 2, 3, 6, 7, 9; chk 2; tt 3-8, 12, 15; dep 4, 7-9;
   ana A-D; ver 3) are likewise unrecorded.
2. **Two decisions the plan's list misses.** C194
   (`proposals/…:5415-5423`) names `io.unsafe_run` as an op frames split,
   which K10 deletes; C187 (`:5342-5346`) names `given_back` among
   `idr.func`'s positional facts, which K13 deletes. Each needs the same
   amendment when its unit lands. C240's sentence on idr-deduplicate
   becomes history if K18 lands.
3. **QB.** The queue's last section says "K21 and K22 are the owner's
   (§4's third question; QB)", but C297 settled QB (`:2917`) and §4 lists
   only QA. The record is inconsistent; K22 waits on K16 alone.
4. **The rederivation plan's coordinator decisions** (`rederive/plan.md`
   §2's last list: C1, C2, C5, C7-C20 of the carriers, each "open to the
   owner's review") are not recorded in §3; only its six questions are
   (C291-C295).
5. **C215**'s second clause (the constant analysis built on sparse
   constant propagation reads the never-folded list) has no subject since
   D132 deleted idr-constants; the e-graph reads the list. Moot, not wrong.

## DONE

C131 to C279 hold as recheck 6 read them; each line below is the
evidence re-read at HEAD (commits as recheck 6 gives them, all before
3beee5fd0, unless named).

- C131 `harness/Facts.idr:53` (`readEnding`), `tests/endings`; C132
  `harness/Programs.idr`, no `actions-skip-programs`; C133 nine
  `tests/scale-*`; C134 `harness/harness.ipkg:9`; C135 `harness/Lit.idr:4`;
  C137 `tools/idris-mlir-tblgen.cpp:7`; C138 `runtime/Alloc/Peaks.cpp:42`,
  `Spec/Runtime/Endings.idr:158`; C139 `lib/IR/Tail.cpp:212` (`tailsOf`);
  C140 `Spec/Lifetimes/Kind.idr:25`, `lifetime.forget`; C143
  `Spec/Grades/Declarations.idr:7`; C144 `lib/IR/OpsArrayFusion.cpp:141`;
  C145, C146, C147, C160 `Spec/Lifetimes/Declarations.idr` (`reserve` at
  `:730-737`; see contradiction 1); C148 `Kind.idr:25` (`Home Nat`); C150
  `compiler/src/IdrisMLIR/Term.idr:417` (`ReadBack`); C152
  `Generated/IdrOps.td`, 8 `MemRead<Idr_ContentsResource>`; C153
  `Spec/Pipeline/Pipeline.idr:295`; C154 no `Dec` built in a library
  body; C155 `Spec/Ops/Numeric.idr` laws; C157 no greedy driver; C158
  `Spec/Ops/Values.idr:7`; C159 `lib/IR/Func/Values.cpp:95`; C161
  `IdrOps.td:2565`; C162 `lib/IR/Grades.cpp`; C164 `tests/spec-current`;
  C165 `upstream/78-*` without a patch; C166 `lib/IR/Control/LiteralMatch.cpp:68`,
  `lib/Analysis/Ranges.cpp:115`; C167, C176 `lib/IR/Tail/Destinations.cpp`;
  C168 `runtime/idris_rt.h`; C169 `runtime/Strings/Simd.h:21`; C170,
  C181, C182 `include/idr/IR/Lifetimes.h:180` (`StatesOuters`); C171,
  C179 `Spec/Tail/Declarations.idr:20`; C172 `tools/bootstrap.sh`; C173,
  C190 `InPlace/UniqueResults.cpp:327`; C174 `Translate/Choices.idr`;
  C175 semi-naive translation (`Frontend/Finite.idr`; D44's engine is
  recheck 7's open item); C177 `tests/runtime-frame-bound`; C178
  `Analysis/Solver/TypeGraph.h:92`; C180 `Spec/Arrays/Memory.idr:319`;
  C183 `checker/src/Core/TT/Stored.idr`; C184 no header beside a `.cpp`.
- C186 `runtime/Alloc/Peaks.cpp`, `tests/shipped-accounts`; C187
  `upstream/99-*`, `tests/upstream-function-interface-edits` (see
  contradiction 2); C188 `InPlace/Rule.cpp:63`; C189
  `Tail/Frames.cpp:158`, `ProgramGraph.h:163`; C191
  `EGraph/Engine.h:14`; C192 `Spec/Counting/Declarations.idr:32`; C193
  `Registry/Faster.idr`; C194 `Spec/Closures/Memo.idr` (see
  contradiction 2); C195 `Ownership/Exclusive.cpp`; C196
  `Spec/Ops/Platform.idr`; C197 `Spec/Core/Op.idr:299`,
  `Spec/Ops/Checks.idr:342`; C198 `Spec/Core/Admitted.idr:61`; C199
  `Makefile:12`; C200 `Support/Match.h:179`; C202
  `Analysis/Ownership/Facts.h:396`; C203 `Optimize/Tails.h:34`
  (`decideTails` on the walk; C294 in flight); C204 no `index_switch` in
  `compiler/src`; C205 `EGraph/Engine.h:19-35`; C206 `lib/IR/Tail.cpp:52`
  (C293 amends it, in flight); C207, C208, C214 their files; C209
  `IR/FlowEdges.h:203`; C210 `Driver/Main.cpp`; C211 `Ranges.cpp:115`;
  C215 the never-folded math lowered in `idr-lower` (contradiction 5);
  C216 `checker/src/Idris/Syntax/Tree.idr`; C218 as D127 reverses its
  first settlement; C219 `Translate/State.idr:1067`; C220
  `Translate/Boundary.idr`; C221 `Translate/Contraction.idr`; C223
  `Growth/Graph.idr:21`; C224 `Growth/Graph.idr:1907`.
- C226 `foreign/idr/CMakeLists.txt:21-45`, `tools/bootstrap.sh:926`, as
  D115 amends it; C227 `Growth/Template.idr:37`; C229 no Python program,
  `tests/dialects-current`; C231 `Growth/Implementations.idr:42`; C233
  no `compiler/idris/` (0a40aec1e); C234 `Translate/Instances.idr:890`;
  C236 `Analysis/Solver/Extraction.h:1-11`; C237 the checker's parsers
  total; C238 `Analysis/Solver/Schedule.h:6`, no atomic in the solver
  layer; C239 `lib/IR/Func/Verifier.cpp:152`; C240
  `Emit/Bodies.idr:4`; C241 `IR/Func.h:258`; C242 `State.idr:93`; C244
  `Spec/Tail/Declarations.idr:184`, `lib/IR/Tail.cpp:43-52`; C247
  `Spec/Core/Interfaces.idr:106`, `Analysis/IdentitiesRecord.cpp:198`;
  C248 `Term.idr:1339`; C249 `State.idr:638`; C250
  `Conversion/Elements.cpp:109`; C252
  `Spec/Closures/Declarations.idr:7`; C253 no `!idr.token`; C254
  `Growth/Graph.idr:37`; C255 `State.idr:1129`; C259 `State.idr:172`;
  C260 `State.idr:1315`; C261 `Translate/Programs.idr:459`; C263
  `Instances.idr:160`.
- C265 `lib/IR/Tail.cpp:267`; C266 `Transforms/Lifetimes/Lend.cpp:15`;
  C267 `Specialize/Open.cpp:138`; C269 `IR/Counting/Takes.cpp:264`; C270
  `Spec/Counting/Declarations.idr:132`; C271
  `checker/src/TTImp/ProcessTransform.idr`, `tests/pragma-transform/expected:2`;
  C272 bc08f0952 (`State.idr:245` `IndexParam Sort`, `Types.erasedIndices`,
  `Instances.idr:502`; fixture `tests/closure-type-keeps-index`); C276
  `IR/Families/Matching.cpp:38`, `tests/opaque-cast-closed-copy`; C277
  `Open.cpp:72`; C278 `Analysis/Identities.h:15`,
  `IR/Families/Substitute.h:119` (`takenTypes`); C279
  `lib/Transforms/Pipeline.cpp`, `Spec/Pipeline/Pipeline.idr:205-206`
  ("every slice … runs it first", 08c59751e), `Driver/Compile.h:85-88`.
- **C280** 1ecf15893: `Spec/Effects/Resource.idr:100` (`Filling`),
  `Spec/Counting/Declarations.idr:389` (`cell.init` writes it),
  `lib/IR/OpsArrays.cpp:143` (the update region's rule off the tree).
- **C282** 927f82e80, a8b9fa3db: `Spec/Grades/Grade.idr:432-440`
  (`freshClaim` and its proof), asked by `lib/IR/OpsCon.cpp:50-68` and
  `IR/Counting/CellInit.cpp:99`.
- **C285** d378e120e: `Generated/IdrOps.td:1867` (a `decide` template over
  `fold::Where`, `IR/FoldParts.h:4`); `GuardOpInterface` has no `decide`
  (`Generated/IdrInterfaces.td:225-231`).
- **C286** f392a02e4: `Spec/Grades/Declarations.idr:200-203`
  (`uncountedClaims`); `givenClaim`, `forgetClaims`, `flowsLinearly`,
  `readsPart` give 0.
- **C287** 1f225b6b9: `Frontend/Profile.idr:144`
  (`KwPrefixRecordProjections = Elaboration`);
  `tests/prefix-record-projections-off`.
- **C290** 9ac7bb651, 0f71306ac: `EGraph/Engine.h:31-35` (constructor and
  closure constants, attributes only at the write-back); the reindex's
  fold follows C293 (in flight).
- **C296** 050d2d7f6: `checker/src/Core/Normalise/Quote.idr:22-32, 86`
  (`Depth`, `UpTo`, `TooDeep`).
- **C298** f392a02e4, 710b73f10: `Analysis/Ownership/Local.h:313, 428,
  505` (`passageOf`, `entryOf`, `carriedClaim`), asked by
  `Transforms/InPlace/Rule.h:21, 230` and the verifier's local rule; the
  non-local half is §4's second question (the owner).
- **C300** a8d860583, 08c59751e: `Conversion/StaticData.h:91, 216`
  (`Statics`), `Conversion/Lower.cpp:19` (phase 0);
  `idr-lower-statics`, `idr-lower-runtime` 0.
- **C301** 212601684: `Transforms/Counting/Reuse.cpp:140-160` (fuses only
  a take whose type does not claim `unique self`).
- **D132** 177aefcca (with 9ac7bb651, 0f71306ac): `idr-constants` and
  `SummarizedConstantPropagation` 0; callee constants are
  `Transforms/EGraph.h:432` (`CalleeFacts`); `DataFlowSolver` is left to
  Ranges and Narrow.

## NO CODE

C136 (§7's placement), C141 (fixed upstream; no patch carried), C142
(records changed with what they describe), C151 (a measurement record),
C243 (§5.2's wording), C245 (two host primitives in Python stay:
`tools/host.sh:130-149`, `tools/bootstrap.sh:1667-1670`), C251 (a
counting rule), C303 (no home for the binder key beyond its location;
settles U12's question).

## SUPERSEDED

C149 and C163 by C165 (patch 78 not carried); C185's claim level by D122
(`Bufferize/Releases.cpp`'s `bufferClaim = Unique::Self`); C212
withdrawn; C225 by D113, D119 and C237; C230 and C232 withdrawn by D116;
C235 by D126; C275's one reindex classifier by C293 (its code,
`IR/Families/Repacks.cpp`'s `builds`, stands until L18ac lands).
