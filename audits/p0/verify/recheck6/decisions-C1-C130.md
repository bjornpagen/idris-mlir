<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 6: the coordinator's decisions C1 to C130, against HEAD

HEAD was 9f4889dd at start and 1f998972 at finish. Eleven commits landed
in between:
- e72a024f (L12v, `Bufferize/Linear.cpp`);
- 13b0e15e (C280) and e518e35c (C281, the queue), proposal text only;
- 29153f20 (L16em: `Term.idr`, `Emit/Bodies.idr`, `Emit/Closures.idr`,
  `Translate/State.idr`, `Choices.idr`, `Programs.idr`);
- 2d7ee52d (L11z, C279: `Driver/Run.cpp`, `Transforms/Pipeline.cpp`,
  `Pipeline.h`, harness, tests);
- d093dbfb (L17bc: the checker's case trees, `Core/Binary.idr`);
- 3beee5fd and ada7d302 (recheck 6's other reports; D111's note);
- f7271225 (L03aa: `spec.ipkg` generated from `Generator/Package.idr`,
  `Ops/Bigs.idr`, `Tail/Declarations.idr`, `IdrOps.td`, `OpsBigs.cpp`);
- b2a2c4ae (the queue);
- 258be23d (L06j: patch 27, `PINS.md`, its test) and 1f998972
  (recheck 6's rules sweep).

Every cited line in the files those commits touch was read again at
d093dbfb, f7271225 or 1f998972 (`PINS.md:333-341, 1327, 1342`; patch
27's directory and check still exist): `Term.idr`, `Emit/Bodies.idr`, `Emit/Closures.idr`,
`Translate/State.idr`, `CaseBuilder.idr`, `Core/Binary.idr`,
`harness/Lit.idr`, `harness/Determinism.idr`, `spec.ipkg`,
`Generator/Outputs.idr`, `Generator/Main.idr`, `Ops/Bigs.idr`,
`Tail/Declarations.idr`, `IdrOps.td`, and the five tests the commits
changed. No verdict changed. Two rows gained a note: C74 (29153f20 took
`Acyclic` and `MayDiverge`'s names out of the frontend's `Termination`)
and C7 (f7271225 generates `spec.ipkg`). None of the six new proposal
entries (C280, C281, D111's note) amends a decision in this range.

Nothing was built, typechecked, generated or run.

**Scope.** Every decision from C1 to C130 in `proposals/0000-mlir-native.md`
§3 was checked, with each later decision or ruling that amends, sharpens
or supersedes one. These are read inside their rows:
- the amendments recheck 5 already read (C142, C144, C156 to C158, C162,
  C164, C166, C167, C168, C171, C173, C176, C180, C186, C189, C190,
  C193, C195 to C197, C200, C201, C203, C204, C208, C218, C235, C236,
  C250, C253; D77, D79, D83, D88, D90, D94 to D96, D98, D102, D108,
  D110, D118 with C233, D122, D124);
- those made since recheck 5:
  - C123 sharpened (`StaticReading` is its form);
  - C126 amended (the comparison withdrawn, tests in its place);
  - C166 amended (a literal case binds the scrutinee);
  - C203 sharpened (one downward walk);
  - C269 and C270 (on C87);
  - C271 (on C55);
  - D126, which supersedes C235.

C235, C269, C270 and C271 have rows of their own in
`decisions-C131-C279.md`, so they add no row here. The table keeps
recheck 5's 148 rows, so the counts compare one for one.

**Starting point.** Recheck 5's verdicts
(`recheck5/decisions-C1-C130.md`). Every row recheck 5 left non-Done was
read again in the code. Every Done row was re-checked for a regression
with one grep count or one read line.

**Conventions.**
- Paths are under `foreign/idr/` unless they start with another
  top-level directory. `spec/` means `compiler/spec/IdrisMLIR/Spec/`;
  `Translate/` and `Growth/` are under `compiler/src/IdrisMLIR/Frontend/`.
- Every line was read from committed text (`git show <rev>:`), never the
  working tree.
- Grounds are *read* (the cited line was opened) or *measured* (a
  `git grep` count; the pattern is given where it is not obvious).
- Owners are from `ownership.json`.
- At finish the working tree held another lane's uncommitted edits to
  files some rows cite: `Emit/Bodies.idr`, `Emit/Operations.idr`,
  `Emit/Index.idr`, `Translate/State.idr`, `Choices.idr`, `Programs.idr`,
  `Term.idr`, `spec/Families/Ops.idr`, `spec/Grades/*`, `OpsCon.cpp`,
  `checker/TTImp/Elab/Ambiguity.idr` and `Check.idr`. Those rows are
  marked *in flight*, and a dispatch into those files waits for that
  lane to land.

## C1 to C20

- **C1** Done. Reuse is guided by the drops already placed
  (`lib/Transforms/Counting/Reuse.cpp:3-6`). The borrow rule is at
  `lib/Analysis/Ownership/Borrows.cpp:9-19`.
  - The counting `Uses.cpp` and `Reuses.cpp` are gone (measured: 0).
  - There is no `DataFlowSolver` in `Analysis/Ownership` or
    `Transforms/Counting` (measured: 0). (read, measured)
- **C196** (on C1 and C24), with C189: Done.
  - No loan spans a call on the caller's own cycle (`Borrows.cpp:21-27`).
  - `io.file_time` and one `handle.file_time <field>` op are at
    `spec/Ops/Platform.idr:226-227, 241`. (read)
- **C2** Done for P0's part. `ReleasesForeign` is a typed `ByType` rule
  (`spec/Effects/Declaration.idr:473-474`). R1 and R2 wait for 0007 and
  0020, as C2 says. (read)
- **C3** Done.
  - `FreshIdentity` is `Allocate` on `Identity`
    (`spec/Effects/Declaration.idr:301`).
  - `Expect/Allocation.cpp:21-31` reads the declared heap `Allocate`.
  - `DataConOp::fold` refuses memo cells, `in_place` values and
    once-used values (`lib/IR/OpsCon.cpp:137-141`; the file is in
    flight).
  - `SuspendOp::fold` and `BuildsValue` have 0 hits. (read, measured)
- **C4** (with D102) Done. The accumulator plan's rule, exact
  associativity with an identity, is at
  `lib/Transforms/Tail/AccumulatorPlan.cpp:5-8`.
  `git grep -niE countdown -- foreign/idr`: 0. (read, measured)
- **C5** Partial, unchanged.
  - Done, re-read:
    - `-fstack-clash-protection` (`CMakeLists.txt:431`);
    - GMP's `--enable-alloca=malloc-reentrant`
      (`tools/bootstrap.sh:1103-1104`);
    - `AT_MINSIGSTKSZ` (`runtime/Platform/Linux/Host.cpp:65`);
    - the `[guard | stack | guard | signal stack]` layout
      (`runtime/Start/Start.h:53`);
    - the 4 GiB span and `FlatPagemap` (`runtime/Alloc/Cells.cpp:36-42,
      156`).
  - Missing: the outside-code margin, measured per target. Every target
    entry still calls `idris_mlir_unmeasured_stacks()`
    (`CMakeLists.txt:216-217, 262, 279, 297, 330`). (read, measured)
  - Owner INT, with L11. Remaining: as C201.
- **C6** (with C197) Done.
  - The registry imports the specification's op modules
    (`compiler/src/IdrisMLIR/Registry/Primitives.idr:14-20`).
  - `Primitive` has 0 hits in `include/idr/IR/Traits.h`.
  - C197's `GuardKind` is at `spec/Core/Op.idr:303`. (read, measured)
- **C7** Done in substance, with a records item.
  - The specification is a library in `compiler/spec`. Since f7271225,
    `compiler/spec/spec.ipkg` is generated from `Generator/Package.idr`,
    with its header at `spec.ipkg:3-5`, and it declares no `depends`.
  - specgen is a package of its own that depends on `idris-mlir-spec`
    (`compiler/spec/specgen.ipkg:3-11`).
  - C7's *Corrected* text still says "the generator is the package's own
    executable".
  - Owner: coordinator. Remaining: amend C7's text for the split, which
    the queue's P-1 carried out (INT-21; 8c3ee239, f7271225). (read)
- **C8** Done.
  - `platform.os` folds only from the module's triple
    (`lib/IR/OpsPlatform.cpp:30-50`). Recheck 5's BSD, Windows and
    Cygwin branches are gone: `osName` answers darwin, unix or nothing.
  - The one POSIX path grammar is at
    `compiler/checker/src/Libraries/Utils/Path.idr:20-25`.
  - `maxNumRewrites` has 0 hits. (read, measured)
- **C9** Done. C++26 is set (`CMakeLists.txt:374`). `template for`,
  `^^` and `std::meta::` have 0 hits. (measured)
- **C10** Done. Partition refinement, once, after idr-knots
  (`lib/Transforms/Deduplicate/Deduplicate.cpp:3-8`). Patch 79 is
  carried. `BodyHash` and `BodyEqual` have 0 hits. (read, measured)
- **C11** Done. Every op but the bare ones below takes its family prefix.
  (measured: `grep -ohE 'Idr_Op<"[^".]+"'` over `IdrOps.td` at HEAD: 15)
- **C158** (on C11) Done, with a records item.
  - The 15 bare mnemonics are C158's list, D124's `carrier`, and
    `may_loop`, new since recheck 5 (`spec/Control/Joins.idr:211`;
    `IdrOps.td:717`).
  - C65 names the op `idr.may_loop` itself. But C158's bare list does
    not hold it, and it acts on a resource (it writes divergence,
    `Joins.idr:218`), which C158's rule would prefix.
  - Owner: coordinator. Remaining: add `idr.may_loop` to C158's list as
    C65 names it, or rename it in the change that next touches
    `Control/Joins.idr`. (read, measured)
- **C12** Partial. This is a regression: recheck 5 counted C12 done.
  - Five prose `expected-error`s were added since recheck 5, each
    matching a verifier's message, not a property and not `{{}}`:
    - `tests/owner-ended-after-field-read/owner-ended-after-field-read.mlir:81, 103`;
    - `tests/partial-self-call-diverges/partial-self-call-diverges.mlir:40`;
    - `tests/root-takes-and-gives-nothing/root-takes-and-gives-nothing.mlir:25, 34`.
  - Every other one of the 75 `expected-error` lines names a property
    (`expected <property>:`) or a contract (`contract <name> broken
    by`), or is `{{}}`.
  - `!idr.box<` and `#idr.types<` appear in 0 test files.
  - The queue asked for this form for one of the tests: L19r's item
    wants the root tests "each refused by its message"
    (`handoffs/L16-queue.md:599-601`). (measured, read)
  - Owner L19, after a coordinator ruling. Remaining: the coordinator
    first records whether a verifier's refusal may name its rule by a
    fragment of its message. If not, L19 restates the five as `{{}}`
    (each `@below` already pins the op).
- **C13** Done; closes recheck 5's Missing row (0dfd861f).
  - Each of 5.7's items 1 to 17 has its row in
    `sources/INDEX.md`'s section "Analyses, solvers and dense side
    tables (P0)", with licence and status. Item 4's two papers are
    `reps-1995-ifds` and `sagiv-1996-ide`.
  - The snapshots are recorded under **Snapshots** (`code/go/`,
    `code/wasmtime/`, Carbon's docs, Zig's Air and Sema, egg and egglog).
  - (measured: each title of `5.7-library.md:807-870`, `grep -ciF` in
    INDEX: 1 or more; read)
- **C14** Done.
  - `coerce` takes `Uses` (`compiler/src/IdrisMLIR/Emit/Operations.idr:234-235`,
    in flight).
  - A binder's quantity is never demoted (`Emit/Monad.idr:137-146`).
  - `mostUses`, `heldAs`, `holdFor` and `madeAt` have 0 hits in
    `compiler/src`. (read, measured)
- **C15** Done.
  - `Budgeted` is a policy (`include/idr/Analysis/Solver/Lattice.h:10,
    50-55`).
  - There is one out-of-memory handler (`include/idr/Driver/Tool.h:8-10`).
  - `kNoLimit` has 0 hits. (read, measured)
- **C156** (with D108, on C15) Partial, unchanged. `nodesPerOp = 64` is
  still "Not yet measured" (`spec/Pipeline/Pipeline.idr:296-304`). C264(a)
  now derives the e-graph's byte budget from it too, which makes the
  measurement weigh more. (read)
  - Owner L03, with L14. Remaining: at stage 1, on the owner's machine,
    measure the nodes per op the e-graph needs on the stage-1 module.
    Set `nodesPerOp` to that number, record the build and input in its
    doc, and delete "Not yet measured".
- **C16** Done. `tests/scale-threads/run:4-8` and
  `harness/Determinism.idr:4`. (read)
- **C17** Done; closes recheck 5's row.
  - `tests/faster-rows/run:4-17` compiles every program and refused
    program the runner plans, "a test added to the suite is compared with
    no list to change", through the frontend built without the Faster
    rows.
  - Its `expected` states every program compiled alike.
  - The declared sample is gone (`ls tests/faster-rows`: `expected`,
    `Faster.idr`, `run`). (read)
- **C18** Done. Gives-back is held once (`include/idr/Analysis/Identities.h:3-6`).
  No `Transforms/Identity/` exists. (read, measured)
- **C19** Done. A field is read off the refined type
  (`lib/IR/OpsConReads.cpp:3-9`). (read)
- **C166** (on C19, with its amendment of 2026-10-23) Done.
  - Every region of a literal match binds its scrutinee
    (`lib/IR/Control/LiteralMatch.cpp:41-44`).
  - A case's binding is `Equals{key}`, and the default's is the
    scrutinee (`:62-69`; `spec/Control/Matches.idr:239-244`). (read)
- **C20** Done.
  - `TailKind = NonTail | Tail | ModuloContext` (`spec/Functions/Tail.idr:29`).
  - `TailPosition`, `TailCallPlan`, `Recursion.cpp`, `forTails`,
    `reachesTailCall` and `no_inline` have 0 hits.
  - One reading of tail position (`lib/IR/Tail.cpp:3-6`), lowered
    `musttail` under `tailcc` (`lib/Conversion/Lower/Functions.cpp:175-194`).
    (read, measured)

## C21 to C45

- **C21** Done. `#idr.grade`, `QType` and `holdsOwn` have 0 hits. The
  lifetime kinds are at `spec/Lifetimes/Kind.idr:25`. (read, measured)
- **C144** (on C21 and C86) Done. `StageHolds`, `HoldsDecided` and
  `holdsUndecided` have 0 hits. `uncounted` reads `countingAt`
  (`lib/IR/OpsArrayFusion.cpp:132`). (read, measured)
- **C162** (on C21) Done. No grade attribute exists beside `!idr.graded`
  (measured: 0).
- **C22** Done. `Fit.cpp` and `Newtype` have 0 hits.
  `idr.numeral.to_nat` and `of_nat` are at `spec/Families/Ops.idr:292-336`.
  (read, measured)
- **C142** (on C22 and C104) Done. `proposals/0018-fin-words.md:480`,
  `0017-apple-dmp.md:5-8` and `0011-data-oriented-frontend.md:5-6`.
  (read)
- **C23** Partial, unchanged since recheck 3.
  - The frontend still declares its own `data Signedness = Signed |
    Unsigned` (`compiler/src/IdrisMLIR/Types.idr:72-79`), with the stale
    "`divs` or `divu`" doc.
  - Emit reads it (`Emit/Operations.idr:273, 327`, in flight;
    `Types.idr:463-465`).
  - The specification's `Signedness` (`spec/Ops/Numeric.idr:33`) is
    imported by nothing in `compiler/src` (`git grep -n
    'Spec.Ops.Numeric' -- compiler/src`: 0). (read, measured)
  - Owner L16. Remaining: import the specification's `Signedness` in
    `Types.idr` and Emit; delete the frontend's `data Signedness` and its
    doc; keep `signedness : IntTy -> Spec.Signedness` and
    `likeSignedness`. Not in the queue.
- **C24** Done.
  - The registry reads `nullWord`
    (`compiler/src/IdrisMLIR/Registry/Primitives.idr:364, 367`).
  - The runtime reads `idr::handles::nullHandle`
    (`runtime/Io/Handles.cpp:77, 151`).
  - `io.clock <kind>` is one op (`spec/Ops/Platform.idr:449, 461`).
  - `idris_rt_handle_is_null` has 0 hits. The one `ClockValid`-like hit
    is base's `prim__osClockValid` mapped to the clock kind
    (`Primitives.idr:348`). (read, measured)
- **C25** Done. Only `io.put_str` and `io.put_char`
  (`spec/Ops/IO.idr:72-81`). `PutList` has 0 hits. (read, measured)
- **C26** Done. `QuantityChange = Enter | Leave`
  (`spec/Grades/Declarations.idr:150`, in flight). `UseModel`,
  `EnterModel` and `isLink` have 0 hits. (read, measured)
- **C27** Done. No op of ours transposes. The three `TransposeOp` hits
  in `Generated/` are linalg's admission (`IdrAdmittedLinalg.td:13`).
  (measured)
- **C28** Done. `legalAt` is at `spec/Pipeline/Stage.idr:70-71`. No hand
  `.td` exists outside `Generated/`. (read, measured)
- **C29** Done. `Plan`, `SlotTypeConverter`, `RetypePattern` and
  `PatternsCalls` have 0 hits in `Defunctionalize/`.
  `Memoized | ByName` is at `spec/Families/Dialect.idr:101`.
  (read, measured)
- **C30** Done. `enum class Link { Include, Unify }`
  (`include/idr/Analysis/Labels.h:114`). (read)
- **C31** Done. `lib/Analysis/Effects.cpp`, `solveEffects`,
  `observableRuns`, `LabelsRun` and `idr-effects` have 0 hits. (measured)
- **C32** Partial, unchanged. `upstream/77-dataflow-state-storage/README.md:31-36`
  still says the record "goes here". (read)
  - Owner L06, with L08. Remaining: at stage 1, on the owner's machine,
    measure bytes per anchor for Ranges and Borrows on the patched
    framework against the current marking, on the four targets. Record
    the numbers, with build and input, in that README.
- **C33** Done. `lib/Transforms/Expect/Continuations.cpp:12, 33` reads
  `solver::ProgramGraph`. `SymbolUserMap` has 0 hits. (read, measured)
- **C236** (on C33 and C114) Done. `FunctionId` keys the graph
  (`include/idr/Analysis/Solver/ProgramGraph.h:73-83`), and §5.2 says so
  (`proposals/0000-mlir-native.md:5784`). (read)
- **C34** Done.
  - The one `isInvalidated` is `Decision.h:59`.
  - `MonotoneWorklist`, `FiniteLattice` and `bool backward` have 0 hits.
  - `summarize<CalleesFirst, AtomsProblem>` sits behind `extern
    template` (`include/idr/Transforms/Effects.h:116`). (read, measured)
- **C35** Partial, unchanged. Patches 06, 28 and 63 are retired, but none
  of their READMEs holds the measurement it promises "recorded here
  either way" (`upstream/06-remove-dead-values-unreachable/README.md:112-114`,
  `28-…/README.md:56-58`, `63-…/README.md:31-33`). (read)
  - Owner L06, at INT's qualification on the owner's machine. Remaining:
    run per-function `remove-dead-values` with U1 and U2 nested on
    `idr.func`, and record what it erases beyond our passes, with build
    and input, in the three READMEs.
- **C36** Partial, measurement only. The one clone-and-key template is
  `include/idr/Transforms/Specialize.h:408-460`. `givesExclusive` has 0
  hits; the two `copyable` hits are the standard concept. No record of
  reached pairs, copies, code size, solve time or footprint exists.
  (read, measured)
  - Owner INT, with L08 (L18 holds `Specialize.h`). Remaining: at stage
    1, measure those five numbers on the scale fixtures and record them
    with build and input.
- **C37** Done. `lib/Transforms/Counting/Placement.cpp:3-23`. (read)
- **C38** Done. `modulo_context` is decided at `lib/IR/Tail.cpp:255`
  and checked at `:298-324`. The frontend writes `NonTail`
  (`Emit/Bodies.idr:598, 613, 615`, re-read at d093dbfb).
  `contextAt` and `BoxType` have 0 hits. (read, measured)
- **C167** and **C203** (on C38, with C203's sharpening of 2026-10-23)
  Done.
  - `!idr.dest<T>` refuses a type used once by its type, and a lifetime
    (`spec/Tail/Declarations.idr:48-60`, re-read at f7271225).
  - Tail position is one downward walk, `tailsOf`
    (`include/idr/IR/Tail.h:17, 75, 86`; `lib/IR/Tail.cpp:212-241`).
  - `inTailPosition` and `decide(CallOp)` have 0 hits.
  - `decideTails` (`include/idr/Transforms/Optimize/Tails.h:30-36`) is
    called in nine files, which cover every place the sharpening names:
    `Defunctionalize/Pass.cpp`, `EGraph/Elaborate.cpp`,
    `Inline/Inline.cpp`, `Inline/InlinePass.cpp`,
    `Optimize/CaptureDrops.cpp`, `Specialize/Raise.cpp`,
    `Narrow/Narrow.cpp`, `Tail/Trmc.cpp` and `Tail/Frames.cpp`.
  - `verify(FuncOp)` checks against the same walk (`Tail.cpp:329-339`).
  - (read, measured)
- **C39** Done. `LowerTakeInto` (`lib/Conversion/Lower/Counting.cpp:112`)
  and the one run-time test `LowerMatchUnique` (`:138`). (read)
- **C250** (on C39 and C107) Done. `lib/Conversion/Elements.cpp:110`
  skips the boxed-element test where the array claims `unique self`.
  (read)
- **C157** (on C39, C65 and C113) Done. `git grep -nE
  'applyPatternsGreedily|getCanonicalizationPatterns|hasCanonicalizer =
  1|createCanonicalizerPass|createCSEPass'` over `foreign` and
  `compiler/spec`, outside `Generated/`: 0. (measured)
- **C253** (on C39) Done. `!idr.reuse_token<…>` is at
  `spec/Counting/Declarations.idr:405, 422`. Join points take
  `mlir::TokenType` (`lib/IR/Control/Joins.cpp:108-112`). (read)
- **C40** (with C168) Done. The one `std::atomic` in `runtime/` is the
  output's length (`runtime/Io/Output.cpp:35`). (measured)
- **C41** Done. `effectsCovered`, `byBlock` and `enableVerifier` have 0
  hits. No `Owned*.cpp` exists. `lib/IR/Verify/Linearity.cpp:3-24` is
  the one rule. (read, measured)
- **C42** Done. `lower` is anchored on the program
  (`lib/Conversion/Lower.cpp:3-8`; `spec/Pipeline/Pipeline.idr:621`).
  (read)
- **C43** Partial, measurement only. The tools take
  `IDRIS_MLIR_TOOL_STACK_BYTES` from the target entry
  (`include/idr/Driver/Tool.h:41-42`), with patch 75 carried. Every
  entry still calls `idris_mlir_unmeasured_stacks()`. (read, measured)
  - Owner INT, with L11. Remaining: as C201.
- **C201** (on C5, C43 and C98) Partial, unchanged. The three sizes are
  defined (`CMakeLists.txt:152-153, 178-216`). No target entry records
  them: `idris_mlir_unmeasured_stacks` is called at `:262, 279, 297,
  330`. (read, measured)
  - Owner INT, with L11, on the owner's machine. Remaining: at stage 1,
    on each of the four targets, measure the tools' stack, the signal
    stack and the outside-code margin. Write the three byte counts,
    with build and input, into each target entry, and delete
    `idris_mlir_unmeasured_stacks` and its four calls.
- **C44** Done. The prepared runtime is read only from what
  `--prepare-runtime` wrote (`lib/Driver/ReadRuntime.cpp:3-12`).
  `BitcodeHome` has 0 hits. (read, measured)
- **C186** (on C44) Done. `tests/shipped-accounts/run:4-8`. (read)
- **C45** Done. Upstream's `Inliner`
  (`lib/Transforms/Inline/InlinePass.cpp:23, 40-54`). `inlineCalls`,
  `inlineStep`, `betaReduces`, `callsOnlyBeside` and `no_inline` have 0
  hits. (read, measured)

## C46 to C72

- **C46** Done. Keys are hash-consed in an arena, and a copy's name is a
  digest of its key's canonical bytes
  (`include/idr/Transforms/Specialize.h:47-50, 114-130`). The key
  attributes have 0 hits. (read, measured)
- **C47** Superseded by D98. No DRR `Pat<` exists in our `.td` files.
  (measured)
- **C48** Superseded by D98. No canonicalizer, CSE, canonicalization
  pattern or `max-num-rewrites` remains. (measured)
- **C49** Done. Defunctionalize runs first and knots second
  (`spec/Pipeline/Pipeline.idr:587-588`). (read)
- **C50** Partial. One of recheck 5's four arms is fixed: a token type now
  prints upstream's `token` (`compiler/src/IdrisMLIR/MLIR.idr:148`;
  `Builtin_Token`, `mlir/include/mlir/IR/BuiltinTypes.td:1265`). Three
  arms still answer a state the type allows with dummy text, guarded by a
  comment:
  - `MLIR.idr:153-154`: an idr type prints `none`;
  - `:169-170`: a float prints `0 : <type>`;
  - `:183-185`: a location or an idr attribute prints `unit`.
  - (read)
  - Owner L16. Remaining: give `typeText` and `attrText` an argument
    type of the text-crossing forms only, with no `Idr`, `LocAttr` or
    `FloatAttr` case (a memref's layout takes that type), and delete the
    three arms. The queue names only the token arm, which is done
    (`handoffs/L16-queue.md:481`).
- **C51** Done. Every binder is primed (`spec/Generator/Idris.idr:12`).
  (read)
- **C52** and **C200** Done. **C235** is superseded by D126; its own row
  is in `decisions-C131-C279.md`.
  - The only `get_if` is the fold's own (`include/idr/Support/Match.h:113`).
  - A case that takes every type does not compile (`:23-29, 179, 200`).
  - D126's form holds: a dialect type is no sum, and its facts are
    interface methods (`:8-12`). aaa578c6 removed C235's type fold and
    `DialectTypes`.
  - (measured: `git grep -nE 'std::get_if|holds_alternative|std::visit\b'
    -- foreign/idr runtime`: 3, all in `Match.h`, two of them comments;
    read)
- **C53** Partial, unchanged. The PCH is built
  (`lib/IR/CMakeLists.txt:131-134`; `-fno-pch-timestamp` at
  `CMakeLists.txt:446`). No `-ftime-trace` baseline is recorded. (read,
  measured)
  - Owner INT, on the owner's machine. Remaining: take the
    `-ftime-trace` header cost per unit with and without the PCH, and
    record it with build and input (stage 1).
- **C54** Partial, unchanged. Extensive hardening is on in every
  configuration (`CMakeLists.txt:383`). Its cost in Release is not
  measured. (read)
  - Owner INT, on the owner's machine. Remaining: measure the program
    suite with and without `_LIBCPP_HARDENING_MODE_EXTENSIVE`, and record
    the number (stage 1).
- **C55** Partial. The `%transform` half is done by C271 (fc306c2c,
  214b0c16):
  - `processTransform` checks both sides and stores nothing
    (`compiler/checker/src/TTImp/ProcessTransform.idr:21-47`);
  - `addTransform`, the `transforms` field, its TTC section and the
    methods' generated rules have 0 hits (`git grep -n -i transform` in
    `Core/Context.idr`, `Core/Binary.idr` and
    `Idris/Elab/Implementation.idr`: one unrelated doc line);
  - the checker's case-tree deletions hold (`toCompileCase`,
    `canInline*`, `inlineSafe`, `refersToRuntimeM`, `mkRunTime`,
    `compileRunTime`: 0 at d093dbfb), and `Phase = CompileTime RigCount
    TreeFor` (`Core/Case/CaseBuilder.idr:46, 52`).
  - Remaining: case blocks are still translated as definitions of their
    own named `<parent>.case<k>` (`Translate/Keys.idr:71-78`, `keyOrigin`
    `:89-96`; `Translate/Boundary.idr:530, 566`). No step puts a block's
    tree into its parent as a region. (read, measured)
  - Owner L16. Remaining: emit a `CaseBlock`'s tree in place as a region
    of its parent's match. Then delete `typedBlock`'s case arm and the
    `.case<k>` naming. Waits for the threading lane (C257 and C281) in
    `Translate/`; queued (`handoffs/L16-queue.md:475`).
- **C56** Partial, measurement only. The derivation concludes sizes and
  breadth (`compiler/src/IdrisMLIR/Proof/Sizes.idr:3-19`). The node
  split's products are unmeasured. (read)
  - Owner L16, with INT on the owner's machine. Remaining: measure the
    node split's products at stage 1, and split the flow by node only if
    they are large.
- **C57** Done. No Core dump option remains. (measured)
- **C58** Done. A refusal is an op built from `SomeRule`
  (`compiler/src/IdrisMLIR/Dialect/Idr.idr:37`).
  - `idr.refusals` has 0 hits.
  - The `outsideLanguage` in `Registry/Recognized.idr:270-275` is the
    registry's list of library names refused by a spec rule, not
    `Profile.outsideLanguage`'s restated rules.
  - The `inFlight` in `EGraph/Simplify.cpp:83-99` is a byte counter, not
    `TS.inFlight`. (read, measured)
- **C59** (with D77) Done. The runtime's joined bodies shed `probe-stack`
  (`lib/Driver/LinkRuntime.cpp:79`). Clash protection is on in the
  runtime (`runtime/CMakeLists.txt:154`). (read)
- **C60** Done. `tests/io-buffer/run:4-12` writes past the shipped
  buffer. `IDRIS_RT_IO_BUFFER_SIZE` has 0 hits. The missing page size is
  now a failure (3b316a5f). (read, measured)
- **C61** Done. snmalloc is a patch project (`tools/patches.sh:17-18`).
  Patches 94 and 95 are in PINS (`PINS.md:1327, 1342`, re-read at
  1f998972). (read)
- **C62** Done. `programPrefix = "idr."`
  (`include/idr/Conversion/Mangle.h:20`). (read)
- **C63** Done. One spare chunk is kept (`runtime/Alloc/Frames.cpp:38-48`).
  No pressure signal exists. (read, measured)
- **C64** (with D94) Done.
  - The rows have one writer, callees first
    (`lib/Transforms/Effects/Writer.cpp:3-9`).
  - Containment is checked on functions (`lib/IR/Verify/Program.cpp:203-206`)
    and equality on calls (`lib/IR/Func/Call.cpp:268-269`).
  - `Amount kind = Finite | Unbounded`
    (`spec/Functions/Parameters.idr:66-67`). (read)
- **C65** Done; closes recheck 5's row (3dc79aa3, 5a3c07f1, 8123ffde).
  - `idr.may_loop` is declared with one effect, a write of divergence,
    directly inside each region of `idr.loop`
    (`spec/Control/Joins.idr:199-218`; `IdrOps.td:717`).
  - Emit writes it first in each join region of a loop unless the
    definition is `Terminates c` (`Emit/Bodies.idr:517-522`, re-read at
    d093dbfb).
  - The function-entry seed is gone: the row holds only what the body's
    ops do (`lib/IR/Func/Rows.cpp:157-163`).
  - `LoopToJoin` takes the mark with the repetition
    (`lib/Transforms/Joins/JoinRules.cpp:221-247`).
  - The lowering tells LLVM through the derived row and withholds
    progress from such loops (`lib/Conversion/Matches.cpp:400-430`).
  - (read)
- **C66** Partial, unchanged.
  - The path rule is in place (`compiler/checker/src/Core/AutoSearch.idr`).
  - No test holds C66's discriminator: every `natToFinLT` in the tree
    passes its proof explicitly, and `Cons2` appears nowhere (`git grep
    -nE 'Cons2|natToFinLT' -- . ':!proposals' ':!audits' ':!sources'
    ':!third_party'`: `bench/qsort/Main.idr:88-89`, `Core/TT/Stored.idr`).
    (measured)
  - Owner L19, with L17. Remaining: a test whose expected file shows
    `natToFinLT 3 {n = 10}` elaborating with its proof left to search,
    and `Cons2.idr` refused. Not in the queue.
- **C67** (with D83) Done. No implementation-choice rule is among the
  megamorphic rules (`spec/Core/Rules.idr:36-43`). (read)
- **C68** Done. Knots, then in-place, then deduplicate
  (`spec/Pipeline/Pipeline.idr:588-590`). `EliminateDuplicate` has 0
  hits. (read, measured)
- **C69** Done.
  - `io.exit` takes a `UInt8` (`spec/Ops/IO.idr:156, 168`).
  - Consumption is `Free` on `Count` alone
    (`spec/Effects/Declaration.idr:300`).
  - `term_setup` and `Scratch` have 0 hits. (read, measured)
- **C70** Done. "Declares nothing" is `EffectSet::everything()`
  (`include/idr/IR/Effects/Declared.h:129`). `AcquiresCell` and
  `allocOther` have 0 hits. (read, measured)
- **C71** Done. No pass of ours adopts `LocalAliasAnalysis` (0 hits).
  (measured)
- **C72** Done. `lib/Transforms/Expect/Report.cpp:15-16`. `noalias` is at
  `lib/Conversion/Lower/Functions.cpp:72-86`. `FuncToFunc.cpp` and
  `mayLoop` have 0 hits. (read, measured)

## C73 to C100

- **C73** (with D98, D103) Done. The program pipeline runs no `cse`,
  `canonicalize` or greedy driver (`spec/Pipeline/Pipeline.idr:586-622`).
  (read)
- **C74** (with D102) Done, with a note (29153f20, re-read at d093dbfb).
  - `Termination = Terminates ComponentId | MayDiverge`
    (`compiler/src/IdrisMLIR/Term.idr:1676`).
  - Emit writes `#idr.terminates` only for `Terminates c`
    (`Emit/Closures.idr:74-79`).
  - `absorb`, `TS.loops` and `total' = True` have 0 hits.
  - The note: L16em took `MayDiverge`'s `List1` of names out with
    `Acyclic`, since nothing read them. C74's text still reads
    `MayDiverge (List1 Name)`. The frontend's `Termination` also restates
    the specification's `Termination = Unproved | InComponent Nat`
    (`spec/Functions/Termination.idr:29`), as L16em's commit says.
  - Owner: coordinator for the text (record `MayDiverge` with no names,
    or bring the names back with a reader). L16 holds the restatement,
    queued by L16em. (read, measured)
- **C75** Done. `guards : List (Guard (Fin i))` (`spec/Core/Op.idr:457`).
  Emit's internal errors in `Emit/Operations.idr` have 0 hits.
  (read, measured)
- **C76** Done. `Hooks.h.inc` and `Laws.h.inc` are generated.
  `semilattice()` has 0 hits. (measured)
- **C77** Done. `IdrRules.txt`, `IdrPassRoles.txt` and
  `IdrPassStages.txt` have 0 hits. (measured)
- **C78** (with C164) Done.
  - The manifest fingerprints the printed value of the outputs and the
    generator's sources (`spec/Generator/Main.idr:61-68`), and `generate`
    is pure (`Generator/Outputs.idr:352`).
  - Recheck 5's out-of-range note is closed: the generator's sources are
    `generatorSources`, a typed list (`Main.idr:67`). Since f7271225
    `spec.ipkg` is itself generated from `Generator/Package.idr`. (read)
- **C79** Done. `ErasedBinderOpInterface` (`spec/Families/Dialect.idr:303`).
  One substitution (`include/idr/IR/Families/Substitute.h:3-5`). (read)
- **C80** Partial, unchanged since recheck 3.
  - The registry's `ListType` hook is still declared, and its doc says no
    handler reads it (`compiler/src/IdrisMLIR/Registry/Entry.idr:333-337`).
  - `IsList` is written at `:469` (with `SumHook` at `:420`) and read by
    no one: `promised` matches `IsInPlace` alone
    (`Translate/Types.idr:940-946`).
  - The Faster row on `Prelude.Basics.List`, with its comment, is at
    `Registry/Faster.idr:108-116`.
  - (read, measured: `git grep -nE 'ListType|IsList' -- compiler/src`)
  - Owner L16. Remaining: delete the `ListType` constructor, the
    `IsList` case and its write, and the List row and its comment; keep
    the `pack` and `scalarBytes` rows. Not in the queue.
- **C81** Done. `!idr.box`, `layout::fit`, `solveHeld` and
  `holdsNoComponent` have 0 hits. (measured)
- **C82** Partial, unchanged since recheck 3.
  - Done: `idr.index.assume`, `idr.data.reindex`, the identity hooks
    gone, and one crash default (`missingCase`, `Translate/Cases.idr:240-242`).
  - Remaining: an arm Idris proved impossible is still `Dead` and left
    out of the match (`Cases.idr:258-284`: `data Arm t = Absent | Dead |
    Present t`, `missingArm`, `armsOf`). `Unreachable` carries a location
    only (`compiler/src/IdrisMLIR/Term.idr:365`, re-read at d093dbfb).
    (read)
  - Owner L16. Remaining: give `Unreachable` its justification (the
    impossible constructor, or the clause marked `impossible`), and keep
    such an arm as a case ending in it instead of dropping it in
    `armsOf`. `Term.idr` is in flight. Not in the queue.
- **C83** (with D124) Done. `lend` and `carrier` are at
  `spec/Lifetimes/Declarations.idr:672, 710`. The alias check asks
  `ViewLikeOpInterface` (`lib/IR/Lifetimes/Loans.cpp:72`). The deleted
  names have 0 hits. (read, measured)
- **C84** (with D95, D96) Done. The frame-limited rule is local
  (`lib/IR/Lifetimes/Proof.cpp:3-6`). `lifetime.pack` is at
  `spec/Lifetimes/Declarations.idr:795-796`. (read)
- **C85** (with C208) Done. `include/idr/Analysis/Ownership/Facts.h:316`.
  (read)
- **C86** (with D88, D90; C144 above) Done. `Hold = Counted Unique |
  Scoped Unique | Static` (`spec/Grades/Hold.idr:41`). `madeStatic`,
  `isStatic`, `persistHeld` and `Phantom` have 0 hits. (read, measured)
- **C87** (with C269 and C270, read inside) Done; closes recheck 5's row
  (c889c8d5, 66a4fbcc, 19307ee9, be9a33ef).
  - `count.dup` and `count.drop` take `countedMany`, counted and used
    many (`spec/Counting/Declarations.idr:79-85, 193, 208`). Generated:
    `IdrOps.td:2520-2541`, `isUsedMany` at `lib/IR/Counting/Ops.cpp:39`.
  - The uniqueness test's shared region takes its value at many
    (`Declarations.idr:309-339`).
  - `EndsOwner` marks drop, take, take_into, match_unique and unpack
    (`:121-132, 209, 256, 278, 298, 337`), read by the linearity rule
    (`lib/IR/Verify/Linearity.cpp:6-8`) and counting
    (`lib/IR/Counting/Flow.cpp:148`).
  - Placement moves or takes apart a once value, never dups or drops it
    (`Transforms/Counting/Placement.cpp:10-13`). (read)
- **C88** Done. `lib/Transforms/Counting/Bound.cpp:3-5`;
  `tests/runtime-frame-bound` exists. (read)
- **C89** Done. `in_place` is refused as `HookShape` on a family that is
  not one constructor with fields (`Translate/Types.idr:940-946`).
  `tests/hook-in-place-two-constructors` exists. (read)
- **C90** (with D79) Done. `inPlace` runs right after defunctionalize
  and knots (`spec/Pipeline/Pipeline.idr:589`). Rebuilds are
  `TokenRebuildOp` (`lib/Transforms/InPlace/Sites.cpp:81`). `IdrDemand`
  has 0 hits. (read, measured)
- **C91** Done. `SuccessorSources` and `unknownFrom` have 0 hits, and
  `tests/in-place-crash-case-gives-nothing` exists. (measured)
- **C92** (with C173, C190) Done. `unique::raiseClaims`
  (`include/idr/Transforms/InPlace/Unique.h:136`) runs in idr-in-place
  (`lib/Transforms/InPlace/Writer.cpp:165`), and `uniqueResults` runs
  before `bufferize` (`spec/Pipeline/Pipeline.idr:599-600`). (read)
- **D110 and D122** (on C90 and C92) Done. Per-member `buffers` and
  `selfCells` (`include/idr/IR/Families/FamilyStorage.h:67, 71`). No
  refusal in the `tests/linarray-*` or `tests/vec-pop-then-push`
  expected files. (read, measured)
- **C93** Done. Patches 65 to 71 are carried, with 7
  `tests/upstream-early-exit*` checks. (measured)
- **C94** Done. Upstream's SCF-to-CF patterns
  (`lib/Conversion/Matches.cpp:14, 493`). (read)
- **C95** Done. Contification reads one dominator tree
  (`lib/Transforms/Optimize/Contify.cpp:14-16`). Case-of-case copies only
  the dispatch (`lib/Transforms/Joins/CaseOfCase.cpp:3-8`). (read)
- **C96** (with C167, C171, C176) Done.
  - Frames are indexed by the awaited row
    (`lib/Transforms/Tail/Frames.cpp:5-9`).
  - `dest.answer` is at `spec/Tail/Declarations.idr:147`.
  - `DestType::verify` is at `lib/IR/Tail/Destinations.cpp:32`.
  - `answerTypeOf`, `asAnswer` and `fromAnswer` have 0 hits.
    (read, measured)
- **C97** (with D96, C171) Done. A tail-call operand whose lifetime ends
  with the call is refused (`lib/IR/Tail.cpp:270-293`). (read)
- **C98** Partial, measurement only. The bound is read through
  `DiagnosticInfoStackSize` (`lib/Driver/StackBound.cpp:56`) and recorded
  in `idris_rt_program_built` (`runtime/Start/Entry.cpp:5`). The margin
  is in no target entry. (read)
  - Owner INT, with L11. Remaining: as C201.
- **C99** Partial, unchanged. `PINS.md:333-341` still leaves the op
  parser and printer, a dialect attribute's parser and printer, and
  `eraseOp` through `std::function` to the stage-1 painting. (read)
  - Owner L06, after INT's painting on the owner's machine. Remaining:
    carry one patch per remaining family, each with its
    `tests/upstream-<bug>` and PINS entry, or record the measurement that
    shows it within the stack; then update `PINS.md:333-342`.
- **C100** Done. The heap span is aligned
  (`runtime/Platform/Platform.h:204-211`). `heapRegion`, `MAP_NORESERVE`,
  `ensure_init` and `idris_rt_gmp_init` have 0 hits. (read, measured)

## C101 to C130

- **C101** Done.
  - `idris_rt_exit(uint8_t)` (`runtime/End/End.cpp:315`;
    `runtime/Generated/idris_rt_ops.h:120`).
  - `data Ending` is at `spec/Runtime/Endings.idr:208`.
  - 94 `expected-ending` files exist.
  - The six deleted names and `RootKind::Status` have 0 hits.
    (read, measured)
- **C102** Done. `Idr_SiteAttr` (`include/idr/IR/Generated/IdrTypes.td:421`).
  A crash passes its cause and site (`lib/Conversion/Runtime.cpp:185-190`).
  (read)
- **C103** Done. `runtime/Platform/Posix/Cgroups.cpp:279-290`.
  `LimitRange` sits after `StatsRange` (`runtime/Alloc/Cells.cpp:113,
  172-179`). (read)
- **C104** Done. `proposals/0017-apple-dmp.md:5-8`. (read)
- **C105** Done. The writable `restrict` is only where the cell claims its
  own cells (`lib/Transforms/Bufferize/Releases.cpp:210-216`).
  `UseModel`, `EnterModel`, `lin.use` and `lin.enter` have 0 hits.
  (read, measured)
- **C193** (on C105) Done. `LArray` is an `InPlaceType` entry
  (`compiler/src/IdrisMLIR/Registry/Recognized.idr:139`), with no Faster
  row. (read, measured)
- **C106** Done. `merge` writes `tensor.expand_shape` and
  `collapse_shape` (`compiler/src/IdrisMLIR/Emit/Tensors.idr:479-480`).
  (read)
- **C107** (with C250) Done. `lowerToLoopsUsingSCFForOp` is used in
  idr-ordered-loops (`lib/Transforms/StructureLoops/StructureLoops.cpp:10`).
  `Idr_Iteration` and `getIterations` have 0 hits. (read, measured)
- **C180** (on C107) Done. `idr.array.place_copy` (`IdrOps.td:989`).
  (read)
- **C108** Done. `upstream/27-one-shot-tensor-like-copy/` and
  `64-tensor-like-per-instance/`. (measured)
- **C109** Done. `#idr.mutable` (`spec/Arrays/Memory.idr`).
  `ElementUpdateOp` and `idr.world` have 0 hits, and "world" appears in
  0 lines of `include` and `lib` outside `Generated/`. (measured)
- **C110** Done.
  - A truth is no `bool` (`include/idr/IR/Numeric/Domain.h:13-16`).
  - `SafeDivisor` (`Numeric/Arith.h:8, 48`).
  - The runtime includes `idr/IR/Numeric/Inline.h`
    (`runtime/Big/Arithmetic.cpp:7`). (read)
- **C111** Done. `nonempty` and `finite` are called by the folder
  (`lib/IR/OpsChecks.cpp:66-68`) and the lowering
  (`lib/Conversion/Checks.cpp:79, 86`). `#Fin[n]` is seeded
  (`lib/IR/Ranges.cpp:157`). (read)
- **C112** Done. One capture family (`spec/Closures/Declarations.idr:7-12`),
  with 3 `Idr_ResultUsesMax` in `IdrOps.td`. (read, measured)
- **C113** (with C157, C158, C204, D98) Done.
  - `data Meaning` (`spec/Core/Op.idr:246`).
  - `Values.idr:7` names `idr.platform.os`.
  - `nat.pred` (`spec/Ops/Bigs.idr:312`, re-read at f7271225) and
    `io.unsafe_run` (`spec/Ops/IO.idr:197`).
  - The family constants have 0 hits. (read, measured)
- **C204** (on C113) Done. The frontend writes no `scf.index_switch`
  (`git grep -nE 'index_switch|IndexSwitch' -- compiler/src`: 0).
  (measured)
- **C114** Done. Patches 72 and 74 are carried. `Scc.cpp`, `Vertex` and
  `stronglyConnected` have 0 hits. (measured)
- **C115** Done. `include/idr/Support/Actions.h:3-5`. (read)
- **C116** Done. `RunDeciding` (`spec/Pipeline/Pipeline.idr:187, 616`),
  and `solver::decided` has its caller
  (`lib/Transforms/Narrow/Narrow.cpp:89`). (read)
- **C117** Done. One flat solve per root
  (`lib/Analysis/BindingTimes.cpp:3-5`). (read)
- **C118** Done. Erasure crosses once, from `eraseArgs`
  (`Translate/Closed.idr:411-414`). (read)
- **C119** (with C195) Done. `branch` and the rejoin
  (`include/idr/IR/Quantities.h:39, 69, 78`). No `Exclusive` handle
  exists. (read, measured)
- **C120** Done. The nine deleted names have 0 hits.
  `knownOf(numeric::Bit)` (`lib/IR/OpsChecks.cpp:38`). `StagedPass`
  (`include/idr/IR/IdrDialect.h:168-178`). (read, measured)
- **C121** Done. `matchPin` has 0 hits in code. (measured)
- **C122** Partial, unchanged in substance.
  - Done: a definition's erasure is read once, from `eraseArgs`
    (`Translate/Closed.idr:411-421`).
  - Remaining: the fact is held in two types:
    - `ArgumentAt = NoValue | RuntimeValue Uses`
      (`Translate/State.idr:884`, re-read at d093dbfb, in flight) mirrors
      `Use = Erased | Used Uses` (`Frontend/Resolve.idr:204`), through
      `byQuantity` (`Closed.idr:404-407`);
    - Growth keeps a second `byQuantity : Use -> Stand`
      (`Growth/Sites.idr:1691-1693`), and `standFor Nothing rig …` reads
      the binder's quantity (`:2378`).
    - C122's index case is still left to each instance. (read, measured)
  - Owner L16. Remaining: make C122's one position type, `Absent | Index
    Sort | Runtime Quantity ClosedTerm`, the type `argumentAt` returns.
    Delete `ArgumentAt` and the second `byQuantity`, and have `standFor`
    read the position through `argumentAt`. Waits for the threading lane
    (C257, C281) in `Translate/` and `Growth/`; queued
    (`handoffs/L16-queue.md:474`).
- **C123** (sharpened 2026-10-23) Done; closes recheck 5's row.
  - `StaticReading` is C123's form, as the sharpening records
    (`Translate/State.idr:92`).
  - `closedHeight` has 0 hits in `compiler/src`, so the two stale
    comments in `Growth/Caps.idr` are gone. (read, measured)
- **C124** Done. Only a `Delay` the elaborator inserted moves a `let`
  (`Translate/Closed.idr:284`). (read)
- **C125** Done. `compiler/checker/src/Libraries/Utils/Path.idr:20-25`.
  The five Windows names have 0 hits in `compiler/checker/src`.
  (read, measured)
- **C126** (amended 2026-10-23) Partial. The amendment replaces the
  comparison with tests. Three of the four obligations stand (3b316a5f):
  - `ITypeOrValue` and `Sort = Universe | Known | Unknown`
    (`compiler/checker/src/Idris/Desugar.idr:566`;
    `TTImp/Elab/Ambiguity.idr:478`, in flight).
  - `(a, b)` and `()` each as a type, as a value, and under an unknown
    type with both readings fitting, the default the value:
    `tests/checker-tuple-pair/Main.idr:42-56` and
    `tests/checker-tuple-unit/Main.idr:34-47`, with their expected
    stdout.
  - `(x ** p)` as a type, as a value, and under an unknown type where
    one reading fits (`tests/checker-tuple-dependent-pair/Main.idr:43-56`).
  - Missing: `(x ** p)` under an unknown type where both readings fit,
    upstream's default. No test states it.
  - Missing: linearity in the tuple. L19w's measurement in 3b316a5f's
    message, not repeated here, is 1.4 s, 3.1 s and 33 s at 16, 20 and 24
    components: the tuple pattern grows exponentially. So
    `tests/checker-tuple-wide-pattern`, whose comment promises linear
    work, does not finish in its 120 s.
  - (read; the timing is L19w's, recalled from the commit)
  - Owner L17, running as L17bd ("C126's dependent-pair default and
    linear tuple patterns", `handoffs/L16-queue.md:770`). Then L19 adds
    the dependent-pair test in which both readings fit, unless L17bd
    lands it.
- **C127** Partial, unchanged since recheck 3.
  - Done: `retryGuess` refuses a growth at `LastChance` and postpones
    otherwise.
  - Remaining:
    - `Searched = Found a | Grows Grown`
      (`compiler/checker/src/Core/Unify.idr:186-188`) has no `Repeated`.
      A repeated goal throws `CantSolveGoal` as an ordinary failure
      (`Core/AutoSearch.idr:696-708`).
    - The quote's depth still travels as the `Error` constructor
      `QuoteTooDeep`: thrown at `Core/Normalise/Quote.idr:196`, caught
      at `:65`, with arms at `Core/Core.idr:204, 413, 533, 624`,
      `Core/Context.idr:1036, 1136` and `Idris/Error.idr:124, 782`.
    - (read)
  - Owner L17. Remaining: add `Repeated` to `Searched` and return it from
    `abandonIfCycle`'s test. Make the depth-limited quote return
    `TooDeep` without throwing, and delete `QuoteTooDeep` and its arms.
    None of these files is in flight. Not in the queue.
- **C128** Done. `delayDepth`, `deeper`, `search_timeout`,
  `foreign_impl`, `debug-elab-check` and `processTTImpFile` have 0 hits.
  `nfThreshold` stays, named (`Core/Options.idr:132`). (measured)
- **C129** Done. `CaseBlock : (parent : Name) -> (ordinal : Nat) -> Name`
  (`compiler/checker/src/Core/Name.idr:49`). `outermost` has 0 hits.
  The block is read off its name (`Translate/Keys.idr:74-78`).
  (read, measured)
- **C130** Done.
  - `--idr-expect-at` (`lib/Driver/Options.cpp:174`).
  - The suite turns on `--idr-contracts` (`harness/Lit.idr:120`, re-read
    at d093dbfb; `harness/Programs.idr:252`).
  - `#idr.binder` (`IdrTypes.td:231`).
  - `harness/lib/mlir.sh`, `checked_steps`, `after:` steps and
    `Quantities.cpp`'s `keyOf` have 0 hits. (read, measured)

## Count

148 rows, the same set as recheck 5: one per decision C1 to C130, and the
18 amendment rows recheck 5 kept (C142, C144, C156, C157, C158, C162,
C166, C167 with C203, C180, C186, C193, C196, C201, C204, C236, C250,
C253, and D110 with D122).

| | Recheck 5 | Recheck 6 |
| --- | --- | --- |
| Done | 120 | 124 |
| Partial | 25 | 22 |
| Missing / Not done | 1 | 0 |
| Superseded | 2 | 2 |
| Regressed | 0 | 1 (C12, counted Partial) |

- **Partial (22):** C5, C12, C23, C32, C35, C36, C43, C50, C53, C54,
  C55, C56, C66, C80, C82, C98, C99, C122, C126, C127, C156 and C201.
  - Eleven of them wait only on stage-1 measurements on the owner's
    machine: C5, C32, C35, C36, C43, C53, C54, C56, C98, C156 and C201.
    C99 waits on one of those measurements, then a patch or a record.
- **Superseded (2):** C47 and C48, by D98. C235 is superseded by D126,
  in `decisions-C131-C279.md`'s range.
- **Closed since recheck 5 (5):** C13 (0dfd861f), C17 (d76f1b33), C65
  (3dc79aa3, 5a3c07f1, 8123ffde), C87 (c889c8d5, 66a4fbcc, 19307ee9,
  be9a33ef), C123 (no stale comment left; the sharpening names its form).
- **Moved forward, still Partial:** C55 (its `%transform` half done by
  C271), C50 (one arm of four fixed) and C126 (re-based on its
  amendment; three of four obligations met).
- **Regressed (1):** C12, five prose `expected-error`s in three tests
  added since recheck 5.
- **Records items, rows still Done:** C7 (the specgen package split),
  C158 (`idr.may_loop` bare) and C74 (`MayDiverge` without names).

## Dispatchable items, by owner

**L16** (`compiler/src/`)
1. **C23.** Import the specification's `Signedness` and delete the
   frontend's copy.
   - Files: `Types.idr:72-79` (keep `signedness` and `likeSignedness`,
     `:463-465`, typed by the specification's), and Emit's readers
     (`Emit/Operations.idr:273, 327`).
   - Waits for: the working-tree edits to `Emit/Operations.idr` to land.
   - Not queued.
2. **C50.** Give `typeText` and `attrText` an argument type with no
   `Idr`, `LocAttr` or `FloatAttr` case, and delete the three dummy arms
   (`MLIR.idr:153-154, 169-170, 183-185`).
   - Waits for: nothing.
   - Not queued; the queue's `MLIR.idr:149` item is done.
3. **C80.** Delete the dead list hook.
   - Files: `Registry/Entry.idr:333-337` (`ListType`), `:420, 469`
     (`IsList` and its write), and the List row and its comment,
     `Registry/Faster.idr:108-116` (keep `pack` and `scalarBytes`).
   - Waits for: nothing (no lane holds `Registry/` now).
   - Not queued.
4. **C82.** Give `Unreachable` (`Term.idr:365`) its justification, and
   keep an impossible arm as a case ending in it, not `Dead`
   (`Translate/Cases.idr:258-284`).
   - Waits for: the working-tree edits to `Term.idr` to land.
   - Not queued.
5. **C55, its first half.** Emit a case block's tree as a region of its
   parent, and delete the `.case<k>` naming (`Translate/Keys.idr:71-96`,
   `Boundary.idr:530, 566`).
   - Waits for: the threading lane (C257, C281).
   - Queued at line 475.
6. **C122.** One position type returned by `argumentAt`.
   - Delete `ArgumentAt` (`Translate/State.idr:884`) and the second
     `byQuantity` (`Growth/Sites.idr:1691-1693`).
   - `standFor` (`:2378`) reads through `argumentAt`.
   - Waits for: the threading lane.
   - Queued at line 474.
7. **C56.** Split the flow by node only if stage 1's measurement shows
   the node split's products are large.
   - Waits for: INT's stage-1 build on the owner's machine.

**L17** (`compiler/checker/`)
8. **C127.** Add `Repeated` to `Searched` (`Core/Unify.idr:186-188`) and
   return it from `abandonIfCycle` (`Core/AutoSearch.idr:696-708`).
   - Make the depth-limited quote return `TooDeep` without throwing, and
     delete `QuoteTooDeep` with its arms (`Normalise/Quote.idr:65, 196`;
     `Core.idr:204, 413, 533, 624`; `Context.idr:1036, 1136`;
     `Idris/Error.idr:124, 782`).
   - Waits for: nothing (L17bd holds `Ambiguity.idr` and `Check.idr`,
     not these files).
   - Not queued.
9. **C126.** The dependent pair's default under an unknown type, and a
   tuple pattern linear in its width (`tests/checker-tuple-wide-pattern`).
   - In flight as L17bd.

**L19** (`tests/`, `harness/`)
10. **C12.** Restate the five prose `expected-error`s as `{{}}`:
    - `owner-ended-after-field-read.mlir:81, 103`;
    - `partial-self-call-diverges.mlir:40`;
    - `root-takes-and-gives-nothing.mlir:25, 34`.
    - Waits for: the coordinator's ruling (item 21).
11. **C66.** A test showing `natToFinLT 3 {n = 10}` elaborating with its
    proof left to search, and `Cons2.idr` refused.
    - With L17.
    - Not queued.
12. **C126.** A test of `(x ** p)` under an unknown type where both
    readings fit, upstream's default.
    - Waits for: L17bd, unless L17bd lands it.

**L03** (`spec/Pipeline/`, `spec/Generator/`)
13. **C156.** Set `nodesPerOp` from the stage-1 measurement, and delete
    "Not yet measured" (`Pipeline.idr:296-304`).
    - Waits for: the owner's machine.

**L06** (`upstream/`, `PINS.md`)
14. **C32.** Record patch 77's bytes per anchor on the four targets
    (`upstream/77-…/README.md:31-36`).
    - Waits for: the owner's machine.
15. **C35.** Record the per-function `remove-dead-values` trial in the
    06, 28 and 63 READMEs.
    - Waits for: the owner's machine.
16. **C99.** After the stage-1 painting, carry a patch per remaining
    recursion family or record the measurement (`PINS.md:333-342`).
    - Waits for: the owner's machine.

**INT** (`CMakeLists.txt`; measurements)
17. **C5, C43, C98 and C201.** Measure the tools' stack, the signal stack
    and the outside-code margin on each of the four targets, write them
    into each target entry, and delete `idris_mlir_unmeasured_stacks`
    (`CMakeLists.txt:216-217, 262, 279, 297, 330`).
    - Waits for: the owner's machine.
18. **C36.** The specializer's five numbers (reached pairs, copies, code
    size, solve time, footprint) on the scale fixtures.
    - Waits for: the owner's machine.
19. **C53.** The `-ftime-trace` PCH baseline.
    - Waits for: the owner's machine.
20. **C54.** The cost of extensive hardening in Release, on the program
    suite.
    - Waits for: the owner's machine.

**Coordinator** (`proposals/`, records)
21. **C12.** Record whether a verifier refusal's fixture may match a
    fragment of its message. The queue asked for that form at line
    599-601, and C12 deletes prose `expected-error`s. Item 10 follows the
    ruling.
22. **C7.** Amend the *Corrected* text: the specification is a library
    whose `spec.ipkg` is generated, and specgen is its own package,
    `specgen.ipkg`, depending on `idris-mlir-spec`.
23. **C158.** Add `idr.may_loop` to the bare list, as C65 names it, or
    have it renamed.
24. **C74.** Record `MayDiverge` with no names (29153f20), or have the
    names come back with a reader.

## Queue items already done (to strike)

In `audits/p0/verify/handoffs/L16-queue.md` at b2a2c4ae (unchanged at
1f998972):
- **Line 479:** "`Caps.idr:135, 165` name the deleted `closedHeight`".
  `closedHeight` has 0 hits in `compiler/src`.
- **Line 481:** "`MLIR.idr:149` (`typeText TokenType = "none"`…)". The
  arm now prints `token` (`MLIR.idr:148`). C50's other three arms are
  item 2 above.
- **Line 483:** "After round 3-A: C65's insertion of `idr.may_loop` …;
  C87's callers". Done (3dc79aa3, 5a3c07f1, 8123ffde; c889c8d5).
- **Line 492:** "`Generator/Main.idr:33-52` finds modules by scanning
  `spec.ipkg`'s text". Done: `generatorSources` (`Main.idr:67`), and
  `spec.ipkg` is generated (f7271225).
- **Line 583:** "From L09x (C65): … L02 deletes the function-entry
  divergence seed … L19s adds `may-diverge`". Done (8123ffde; 13a29cf1).
- **Line 599:** "From L19r: the root rule … has no test of its own".
  `tests/root-takes-and-gives-nothing` exists (1af4154c). L19x's
  dispatch names "the root rule's test" again (line 775), which may
  repeat it.
- **Lines 635-638:** "From L02x: `unittests/Rows.cpp`'s model still seeds
  divergence" (L15x, 67cbb873). "Termination's `Acyclic` … delete it" is
  done in the frontend by 29153f20; no termination `Acyclic` remains in
  the C++ (the two hits are `Containment::Acyclic`).
- **Line 749:** "the frontend's `Term.Termination` keeps `Acyclic`".
  Done (29153f20).
- **Line 471:** the sources lane (C13), done (0dfd861f).
- **Line 468:** L19z with C17. C17 is done by d76f1b33.

## Seen outside the range

Recheck 5's notes, at HEAD:
- Closed:
  - `ReadRuntime.cpp`'s two runtime kinds: one runtime path
    (`lib/Driver/ReadRuntime.cpp:3-12`).
  - `osName`'s BSD, Windows and Cygwin branches: gone
    (`lib/IR/OpsPlatform.cpp:30-36`).
  - `modulesOf`'s text scan: gone (see C78).
  - io-buffer's skip: now a failure (3b316a5f).
  - `audits/bugs.md`'s status paragraph: re-dated 2026-10-23, saying its
    entries are unrechecked since b8301ebe.
- Open: the specification's `Termination` is now imported by
  `spec/Functions/Declarations.idr:40` and named as `::idr::Termination`
  (`:245`). `include/idr/IR/Func.h:77` still writes `using Termination =
  std::variant<Unproved, InComponent>` by hand, and the frontend's
  `Term.Termination` restates both (see C74). That is one fact held three
  times (L02, L03, L16).
