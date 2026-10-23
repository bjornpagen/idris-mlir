<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 5: the coordinator's decisions C1 to C130, against HEAD

HEAD was 17725fdd at start and cb5cd6fb at finish. Four commits landed
in between (2bcbd726, 16ac96c4, 59dcc964, cb5cd6fb). They touch only
D126's round 2b-T and 2c-T files, `Match.h` and the queue. Every cited
line in those files was re-read at cb5cd6fb (`Match.h`, `Call.cpp`,
`Frames.cpp`, `ProgramGraph.h`, `Tail.cpp`), and no verdict changed.

Nothing was built, typechecked, generated or run.

**Scope.** Every decision from C1 to C130 in `proposals/0000-mlir-native.md`
§3 was checked, with each later decision or ruling that amends,
sharpens or supersedes it:

- C142, C144, C156, C157, C158, C162, C164, C166, C167, C168, C171,
  C173, C176, C180, C186, C189, C190, C193, C195, C196, C197, C200,
  C201, C203, C204, C208, C218, C236, C250 and C253;
- D77, D79, D83, D88, D90, D94, D95, D96, D98, D102, D108, D110, D118
  with C233, D122 and D124.

An amendment gets a row of its own only where it adds an obligation.
Otherwise it is read inside its decision's row.

**Starting point.** Recheck 3's verdicts
(`recheck3/decisions-C1-C80.md`, `decisions-C81-C160.md`). Every row
recheck 3 left non-Done was read again. Every Done row was re-checked
for a regression with one grep count or one read line.

**Conventions.**
- Paths are under `foreign/idr/` unless they start with another
  top-level directory. `spec/` means `compiler/spec/IdrisMLIR/Spec/`.
- Grounds are *read* (the cited line was opened) or *measured* (a
  `git grep` or `ls` count; the command is given where it is not
  obvious).
- Owners are from `ownership.json`.
- "In flight" marks evidence in a file one of the four writing lanes
  holds (L14x, L16ee, D126 2b-S, D126 2b-T). Such a row reports what
  HEAD's text shows.

## C1 to C20

- **C1** Done. Reuse is guided by the drops already placed
  (`lib/Transforms/Counting/Reuse.cpp:3-6`), and a rebuild is a token
  consumed by `token.rebuild` (`:32-35`). The amended borrow rule is at
  `lib/Analysis/Ownership/Borrows.cpp:9-19`, and a quantity-1 argument
  makes its parameter counted (`:334`).
  - The counting `Uses.cpp` and `Reuses.cpp` are gone. The one
    `lib/IR/Verify/Uses.cpp` is the value-source helper, a different
    unit. No `DataFlowSolver` is used in `Analysis/Ownership` or
    `Transforms/Counting`. (read, measured)
- **C196** (on C1 and C24), with C189: Done.
  - No loan spans a call on the caller's own cycle
    (`lib/Analysis/Ownership/Borrows.cpp:20-27`).
  - `io.file_time` takes and gives a handle; one
    `handle.file_time <field>` op is at `spec/Ops/Platform.idr:226-227,
    241, 255`. Its entries are `field<FileTimeField::…>`
    instantiations (`runtime/Io/FileTimes.cpp:50-67`). (read)
- **C2** Done for P0's part. `ReleasesForeign` is a typed `ByType` rule
  (`spec/Effects/Declaration.idr:473-474`), read at
  `include/idr/IR/Effects/Vocabulary.h:270`. R1's and R2's kernel
  buffers wait for 0007 and 0020, as C2 says. (read)
- **C3** Done.
  - `FreshIdentity` is `Allocate` on `Identity`
    (`spec/Effects/Declaration.idr:301`).
  - `Expect/Allocation.cpp:21-31` reads the declared heap `Allocate`,
    with no hand list.
  - `DataConOp::fold` refuses memo cells, `in_place` values and
    once-used values (`lib/IR/OpsCon.cpp:115-124`).
  - `SuspendOp::fold` and `BuildsValue` have 0 hits.
  - C218 cites C3 but does not amend it. (read, measured)
- **C4** (with D102) Done. Exact associativity with its identity, on
  either side, with no floats and no user `Monoid`
  (`lib/Transforms/Tail/AccumulatorPlan.cpp:5-15`). The laws come from
  the specification (`:116-124`). The self call must carry no crash and
  no divergence (`:39-43`). No countdown recognizer remains
  (`git grep -niE countdown -- foreign/idr`: 0). (read, measured)
- **C5** Partial.
  - Done:
    - `-fstack-clash-protection`, and GMP built with
      `--enable-alloca=malloc-reentrant` (`CMakeLists.txt:431`;
      `tools/bootstrap.sh:1068, 1103-1104`);
    - `AT_MINSIGSTKSZ` (`runtime/Platform/Linux/Host.cpp:65-71`);
    - the `[guard | stack | guard | signal stack]` layout
      (`runtime/Start/Start.h:53`);
    - the span aligned to 4 GiB and the bounded `FlatPagemap`
      (`runtime/Alloc/Cells.cpp:36-42, 156-157`).
  - Missing: the margin for outside code, measured per target. Every
    target entry still calls `idris_mlir_unmeasured_stacks()`
    (`CMakeLists.txt:216-223, 262, 279, 297, 330`). (read, measured)
  - Owner INT, with L11. Remaining: see C201 below, which holds the
    one obligation shared by C5, C43 and C98.
- **C6** (with C197) Done.
  - The registry imports the specification's op modules
    (`compiler/src/IdrisMLIR/Registry/Primitives.idr:14-20`).
  - The `Primitive` trait is gone from `include/idr/IR/Traits.h`
    (0 hits).
  - Base's `prim__` names appear in the specification only in doc prose,
    never as a mapping.
  - C197's `GuardKind` is at `spec/Core/Op.idr:298`. (read, measured)
- **C7** Done; closes recheck 3's row.
  - specgen is the package's own executable, and the package depends on
    base alone (`compiler/spec/spec.ipkg:3, 95-96`), as C7's
    "Corrected" note now reads.
  - `tests/registry-only/run:56-58` now scans `compiler/spec`. (read)
- **C8** Done in code.
  - `platform.os` folds only from the module's triple
    (`lib/IR/OpsPlatform.cpp:33-42`).
  - The PAL's error ends as the runtime's internal error
    (`runtime/Alloc/Cells.cpp:50-54`).
  - There is one POSIX path grammar
    (`compiler/checker/src/Libraries/Utils/Path.idr:19-25`).
  - `maxNumRewrites` has 0 hits.
  - The reproductions for `audits/bugs.md` come at qualification.
    (read, measured)
- **C9** Done. C++26 is set (`CMakeLists.txt:374`). No `template for`,
  `^^` or `std::meta::` appears in `foreign/idr` or `runtime`.
  (measured)
- **C10** Done. Partition refinement over `OperationEquivalence`, once,
  after idr-knots (`lib/Transforms/Deduplicate/Deduplicate.cpp:3-21`;
  `spec/Pipeline/Pipeline.idr:589`). The hook is carried as
  `upstream/79-operation-equivalence-symbol-hook`. `BodyHash` and
  `BodyEqual` have 0 hits. (read, measured)
- **C11** Done. Of the 201 generated ops, 14 have bare mnemonics:
  C158's list, plus `carrier`, which D124 names. (measured:
  `grep -ohE 'Idr_[A-Za-z]*Op<"[^"]+"' include/idr/IR/Generated/*.td`)
- **C158** (on C11) Done. Measured the same way. `idr.refusal` stays
  bare, by C218 (`include/idr/IR/Generated/IdrOps.td:13`). (measured,
  read)
- **C12** Done; closes recheck 3's row. The five prose `expected-error`s
  now name the property or are `{{}}`
  (`tests/contracts-quantities-kept/contracts-quantities-kept.mlir:23`,
  `tests/expect-constant-stack/expect-constant-stack.mlir:66`,
  `tests/linear-cast-forgets-claims/linear-cast-forgets-claims.mlir:37`,
  `tests/linear-fields-each-once/linear-fields-each-once.mlir:41`).
  - The 42 `expected-error` lines in `tests` all name a property.
  - `!idr.box<` and `#idr.types<` appear in 0 test files. (measured)
- **C13** Missing. Recheck 3 counted it done, but no version of
  `sources/INDEX.md` has ever listed the items.
  - `grep -ciF` of each title of `audits/p0/wave1/5.7-library.md:807-870`
    in `sources/INDEX.md` gives 0 for items 1 to 15 and 17. The INDEX
    rows that mention Scholz and Sahebolamri (`:617`, `:858-861`) are
    other papers.
  - Item 16, egg and egglog, is listed "Not vendored" (`:267`).
  - The same three-title grep over every revision of
    `sources/INDEX.md` gives 0 (`git log -- sources/INDEX.md`, six
    revisions). (measured)
  - Owner: `sources/` has no owner in `ownership.json`; the coordinator
    assigns one. Remaining: fetch items 1 to 17, verify their
    identifiers, store each under `sources/papers/` or `sources/code/`
    with its provenance, and add one INDEX row each with its licence and
    status.
- **C14** Done.
  - `coerce` takes `Uses` and only casts
    (`compiler/src/IdrisMLIR/Emit/Operations.idr:226-244`).
  - A binder's quantity is never demoted
    (`compiler/src/IdrisMLIR/Emit/Monad.idr:137-146`).
  - `mostUses`, `heldAs`, `holdFor` and `madeAt` have 0 hits in
    `compiler/src`.
  - The aliased binding is at `Frontend/Translate/Terms.idr:879-912`
    (in flight, L16ee). (read, measured)
- **C15** Done.
  - `Budgeted` is a policy of its own type
    (`include/idr/Analysis/Solver/Lattice.h:10, 50-55`), and a budgeted
    problem must have a top (`Summarize.h:41-42`).
  - There is one out-of-memory handler
    (`include/idr/Driver/Tool.h:109-110`).
  - `kNoLimit` has 0 hits, and no refusal analysis is budgeted.
    (read, measured)
- **C156** (with D108, on C15) Partial. `nodesPerOp = 64` is still
  documented "Not yet measured" (`spec/Pipeline/Pipeline.idr:296-303`).
  (read)
  - Owner L03, with L14. Remaining: at stage 1, measure the nodes per op
    the e-graph needs on the stage-1 module, set `nodesPerOp` to that
    number with its build and input in the doc, and delete "Not yet
    measured". This needs a build.
- **C16** Done. `tests/scale-threads/run:4-30` compares every artifact
  at one thread and on the pool. `harness/Determinism.idr:180-190` does
  the same for the module, statistics and remarks. (read)
- **C17** Partial.
  - Done: hooks are indexed by `Kind`, with `Lowers` admitting only
    `Contract` and `Faster`
    (`compiler/src/IdrisMLIR/Registry/Entry.idr:274, 290-294`).
  - Short: `tests/faster-rows/run:4-17` compares only a declared sample
    of 8 programs (5 accepted, 3 refused, `tests/faster-rows/sample`),
    where C17 says "each program". The run's own comment gives cost as
    the reason. (read)
  - Owner L19. Remaining: compare every program test whose cases fit
    the limits through the Faster-less frontend, or have the coordinator
    narrow C17's "each program" to a declared sample with its reason.
- **C18** Done. Gives-back is held once on `idr.func`, per result field
  path (`include/idr/Analysis/Identities.h:3-13`;
  `spec/Functions/GivenBack.idr:3-7`). No `Transforms/Identity/` exists.
  (read, measured)
- **C19** Done. A field is read off the refined type, with no
  enclosing-match walk (`lib/IR/OpsConReads.cpp:3-9`). (read)
- **C166** (on C19) Done. A literal match's default is refined to the
  complement (`spec/Control/Matches.idr:23, 239`).
  `lib/IR/Control/LiteralMatch.cpp` is in flight (2b-S). (read)
- **C20** Done. `TailKind = NonTail | Tail | ModuloContext`
  (`spec/Functions/Tail.idr:24-28`).
  - `TailPosition`, `TailCallPlan`, `Recursion.cpp`, `forTails`,
    `reachesTailCall` and `no_inline` have 0 hits.
  - There is one definition of tail position (`lib/IR/Tail.cpp:3-5`),
    lowered as `musttail` under `tailcc`
    (`lib/Conversion/Lower/Functions.cpp:164-165, 214`). Both files are
    in flight (2b-T). (read, measured)

## C21 to C45

- **C21** Done. The grade is the `Hold` value class, from generated
  tables (`include/idr/IR/Grades.h:64-111`). `#idr.grade`, `QType` and
  `holdsOwn` have 0 hits. The lifetime kinds are at
  `spec/Lifetimes/Kind.idr:25`. (read, measured)
- **C144** (on C21 and C86) Done; closes recheck 3's three rows.
  - `StageHolds`, `HoldsDecided` and `holdsUndecided` have 0 hits. The
    stage table keeps `StageCounting` and `countingAt` only
    (`spec/Pipeline/Stage.idr:85, 151-154`).
  - `uncounted` now reads `countingAt[...] == StageCounting::Uncounted`
    (`lib/IR/OpsArrayFusion.cpp:130-132`).
  - `lib/Transforms/Joins/YieldedFields.cpp:32` holds its rule at every
    stage.
  - The one remaining `Undecided` hit is an unrelated planted-fault
    name (`unittests/Intervals.cpp:253`). (read, measured)
- **C162** (on C21) Done. No grade attribute exists beside
  `!idr.graded`. The hold is parsed as the type's parameter
  (`lib/IR/Grades.cpp:21-60`). (read, measured)
- **C22** Done. `Fit.cpp` and `Newtype` are gone. The
  `idr.numeral.to_nat` and `of_nat` ops are at
  `spec/Families/Ops.idr:306, 336`. (read, measured)
- **C142** (on C22 and C104) Done. The cross-proposal amendments are
  written: `proposals/0018-fin-words.md:480`,
  `proposals/0017-apple-dmp.md:5-11` and
  `proposals/0011-data-oriented-frontend.md:5-8`. (read)
- **C23** Partial, unchanged since recheck 3. (read, measured)
  - `compiler/src/IdrisMLIR/Types.idr:70-82` still declares its own
    `data Signedness = Signed | Unsigned`, with the stale "`divs` or
    `divu`" comment.
  - Emit reads it (`Emit/Operations.idr:273, 318, 327`).
  - The specification's `Signedness` (`spec/Ops/Numeric.idr:33`) is
    imported by nothing in `compiler/src` (`git grep -n
    'Spec.Ops.Numeric' -- compiler/src`: 0).
  - Owner L16. Remaining: import the specification's `Signedness` in
    `Types.idr` and Emit; delete the frontend's `data Signedness` and
    its comment, and keep `signedness : IntTy -> Spec.Signedness`.
- **C24** Done; closes recheck 3's row.
  - The null handle is held once, in
    `spec/Runtime/Handles.idr:36-43, 80`.
  - The registry reads `nullWord`
    (`compiler/src/IdrisMLIR/Registry/Primitives.idr:18, 364, 367`).
  - The runtime reads `idr::handles::nullHandle`
    (`runtime/Io/Handles.cpp:77, 151`).
  - `io.clock <kind>` is one op (`spec/Ops/Platform.idr:449, 461`), and
    its runtime entries are one template (`runtime/Io/Clock.cpp:21-48`).
  - The clock-valid ops and `idris_rt_handle_is_null` have 0 hits.
    (read, measured)
- **C25** Done. Only `io.put_str` and `io.put_char` remain
  (`spec/Ops/IO.idr:72, 80`). The number writers are helpers of the
  show (`spec/Ops/Strings.idr:97-128`). `PutList` has 0 hits.
  (read, measured)
- **C26** Done. `lin.cast` with `QuantityChange = Enter | Leave` is at
  `spec/Grades/Declarations.idr:150, 277, 297`. `UseModel`, `EnterModel`
  and `isLink` have 0 hits. The sharers are a partition built once
  (`lib/Transforms/Bufferize/Releases.cpp:156-159`). (read, measured)
- **C27** Done. No `TransposeOp` of ours exists. The frontend writes
  `linalg.transpose` (`compiler/src/IdrisMLIR/Emit/Tensors.idr:402-424`).
  (read, measured)
- **C28** Done. Ops carry `legalAt` (`spec/Pipeline/Stage.idr:70-72`)
  and passes carry their stages (`spec/Pipeline/Pass.idr:58-83`). No
  hand `.td` exists outside `Generated/`. (read, measured)
- **C29** Done. `Plan`, `SlotTypeConverter`, `RetypePattern` and
  `PatternsCalls` have 0 hits in `Transforms/Defunctionalize/`.
  `Memoized | ByName` is at `spec/Families/Dialect.idr:97-103`.
  (read, measured)
- **C30** Done. `Link { Include, Unify }` and the union-find are at
  `include/idr/Analysis/Labels.h:52, 114-126`. (read)
- **C31** Done. `lib/Analysis/Effects.cpp`, `solveEffects`,
  `observableRuns`, `LabelsRun` and `idr-effects` are gone.
  (read, measured)
- **C32** Partial, unchanged.
  - `upstream/77-dataflow-state-storage/README.md:31-36` says the number
    "goes here", and it is not there.
  - Borrows already runs on the solver layer's marking, not on
    `DataFlowSolver` (`lib/Analysis/Ownership/Borrows.cpp:28-46`). So
    the order C32 states (the patched framework's number taken first)
    was not kept. (read, measured)
  - Owner L06 (`upstream/`), with L08. Remaining: at stage 1, measure
    bytes per anchor for Ranges and for Borrows on the patched framework
    against the current marking, on the four targets, and record the
    numbers with build and input in the README. This needs a build.
- **C33** Done; closes recheck 3's row.
  - `lib/Transforms/Expect/Continuations.cpp:20-47` reads
    `solver::ProgramGraph`.
  - `SymbolUserMap` has 0 hits in `foreign/`.
  - `ProgramGraph.h:9-31` wraps the one `mlir::CallGraph`, through
    patch 73. (read, measured)
- **C236** (on C33 and C114) Done. Every table is keyed by
  `FunctionId` (`include/idr/Analysis/Solver/ProgramGraph.h:9-31`), and
  §5.2 is corrected (`proposals/0000-mlir-native.md:5496`). (read)
- **C34** Done; closes recheck 3's L04 and L14 rows.
  - The only `isInvalidated` in `foreign/` is the `ReadsAnalyses`
    template (`include/idr/Analysis/Solver/Decision.h:56-60`;
    `git grep -n isInvalidated -- foreign`: 1).
  - `MonotoneWorklist`, `FiniteLattice` and `bool backward` have 0 hits.
  - `summarize<CalleesFirst, AtomsProblem>` sits behind
    `extern template` (`include/idr/Transforms/Effects.h:113-114`).
    (read, measured)
- **C35** Partial.
  - Patches 06, 28 and 63 are retired: their directories hold no
    `llvm.patch`.
  - Each README promises the measurement "recorded here either way"
    (`upstream/06-remove-dead-values-unreachable/README.md:112-114`),
    and none holds it. (read, measured)
  - Owner L06, at INT's qualification. Remaining: run per-function
    `remove-dead-values` with U1 and U2 nested on `idr.func`, and record
    what it erases beyond our passes, with build and input, in the 06,
    28 and 63 READMEs. This needs a build.
- **C36** Partial, measurement only.
  - The one clone-and-key template is
    `include/idr/Transforms/Specialize.h:270-342`.
  - `givesExclusive` and `copyable` have 0 hits.
  - No record exists of reached pairs, copies, code size, solve time or
    footprint. (read, measured)
  - Owner INT, with L08. Remaining: at stage 1, measure those five
    numbers on the scale fixtures and record them with build and input.
- **C37** Done. Drops go after last use, a value used once is never
  duplicated, and nothing is placed after a tail or modulo-context call
  (`lib/Transforms/Counting/Placement.cpp:3-19`). (read)
- **C38** Done (in flight, 2b-T). `modulo_context` is decided at
  `lib/IR/Tail.cpp:126` and checked at `:180`. The frontend writes
  `NonTail` (`compiler/src/IdrisMLIR/Emit/Bodies.idr:573-590`).
  `contextAt` and `BoxType` have 0 hits. (read, measured)
- **C167** and **C203** (on C38) Done. `!idr.dest<T>` refuses a type
  used once by its type, and a lifetime
  (`spec/Tail/Declarations.idr:48-71`). The frontend writes every call
  `nontail` (`Emit/Bodies.idr:573`). (read)
- **C39** Done; closes recheck 3's L21 row. `LowerTakeInto` takes only a
  `Unique::Self` value and makes no test
  (`lib/Conversion/Lower/Counting.cpp:105-134`). The one run-time test
  is `LowerMatchUnique` (`:138-167`), made by counting for every other
  take (`lib/Transforms/Counting/Expand.cpp:3-24`). (read)
- **C250** (on C39 and C107, as corrected the same day) Done.
  `lib/Conversion/Elements.cpp:109-127` keeps the one boxed-element test
  (`BoxSharing::AtRunTime`) and skips it where the array claims
  `unique self`. C250's correction rules exactly this, so recheck 3's
  Elements row under C39 and C107 is superseded by C250. (read)
- **C157** (on C39, C65 and C113) Done. No greedy driver and no
  canonicalization pattern exist in our code (`git grep -n
  'applyPatternsGreedily\|getCanonicalizationPatterns\|hasCanonicalizer
  = 1\|createCanonicalizerPass' -- foreign compiler/spec`: 0 outside
  `Generated/`). The join and loop rewrites are rooted rules
  (`spec/Control/Rules.idr:51-63`). (measured, read)
- **C253** (on C39) Done. `!idr.reuse_token<…>` is at
  `spec/Counting/Declarations.idr:359-389`. Join points take
  `mlir::TokenType` (`lib/IR/Control/Joins.cpp:105`). (read)
- **C40** (with C168) Done. No atomic count exists in `runtime/`. The
  one `std::atomic`, `runtime/Io/Output.cpp:35`, is the output's
  length. No signed or sticky encoding was introduced. (measured)
- **C41** Done. `Owned*.cpp`, `effectsCovered` and `byBlock` are gone.
  `lib/IR/Verify/Linearity.cpp:1-21` is the one linearity rule. No
  `enableVerifier` call exists. (read, measured)
- **C42** Done, against its recheck 3 correction. `lower` is anchored
  on the program (`lib/Conversion/Lower.cpp:1-23`;
  `spec/Pipeline/Pipeline.idr:462-474`). No worker-and-merge scheduler
  is left. (read)
- **C43** Partial, measurement only.
  - The 2^36 reservation is gone.
  - The tools take `IDRIS_MLIR_TOOL_STACK_BYTES` from the target entry
    (`include/idr/Driver/Tool.h:41-83`).
  - Patch 75 is carried (`upstream/75-thread-pool-stack-size/`).
  - Every entry still calls `idris_mlir_unmeasured_stacks()`.
    (read, measured)
  - Owner INT, with L11. Remaining: as C201.
- **C201** (on C5, C43 and C98) Partial. The three sizes are defined at
  `CMakeLists.txt:178-210` as C201 says, but no target entry records
  them (`grep -n unmeasured_stacks CMakeLists.txt`: 5, at `:216-223,
  262, 279, 297, 330`). Configure refuses until they are given.
  (read, measured)
  - Owner INT, with L11. Remaining: at stage 1, on each of the four
    targets, paint and measure the tools' stack, the signal stack and
    the outside-code margin. Write the three byte counts, with build and
    input, into each target entry, and delete
    `idris_mlir_unmeasured_stacks` and its four calls.
- **C44** Done. Recheck 3 called this Partial; this recheck reads it
  again.
  - The prepared runtime is read only from the bitcode file beside its
    object (`lib/Driver/ReadRuntime.cpp:293-310`).
  - `BitcodeHome` has 0 hits.
  - The section reading recheck 3 named (`findBitcodeInMemBuffer`,
    `:69-97`) reads the archive's members, which are the input to
    `--prepare-runtime`, not the prepared runtime. Their two flag sets
    are target-entry facts (`CMakeLists.txt:231, 316`). (read, measured)
- **C186** (on C44) Done. `tests/shipped-accounts/run:4-21, 95-98`.
  (read)
- **C45** Done (in flight, 2b-T). Upstream's `Inliner` is used
  (`lib/Transforms/Inline/InlinePass.cpp:40-54`). `inlineCalls`,
  `inlineStep`, `betaReduces`, `callsOnlyBeside` and `no_inline` have
  0 hits. (read, measured)

## C46 to C72

- **C46** Done. Keys are interned in an arena as a closed sum, and a
  copy's name is a digest of the key's canonical bytes
  (`include/idr/Transforms/Specialize.h:30, 87-107, 204-225`). The four
  key attributes have 0 hits. (read, measured)
- **C47** Superseded by D98. No DRR `Pat<` exists in our `.td` files.
  (measured)
- **C48** Superseded by D98. No greedy driver and no `max-num-rewrites`
  patch exist. D98 itself holds: no canonicalizer, CSE or
  canonicalization pattern in our code (`git grep -nE
  'createCanonicalizerPass|createCSEPass|getCanonicalizationPatterns'
  -- foreign/idr compiler/spec`: 0). (measured)
- **C49** Done. Defunctionalize runs first and knots second, with
  nothing simplifying before them (`spec/Pipeline/Pipeline.idr:584-589`).
  (read)
- **C50** Partial, unchanged since recheck 3. The text printer still
  answers four states the type allows with dummy text. Each arm's guard
  is a comment, not the representation. (read)
  - `compiler/src/IdrisMLIR/MLIR.idr:148-149`: a token type prints
    `none`.
  - `:154-155`: an idr type prints `none`.
  - `:170-171`: a float prints `0 : <type>`.
  - `:184-186`: a location or an idr attribute prints `unit`.
  - Owner L16. Remaining: give `typeText` and `attrText` an argument
    type of the text-crossing forms only, with no `Idr`, `LocAttr`,
    `TokenType` or `FloatAttr` case (a memref's layout takes that type),
    and delete the four arms.
- **C51** Done. Every binder is primed, and builders take a `Value`, a
  `Maybe Value` or a `List Value` per group
  (`spec/Generator/Idris.idr:36-58, 196-199`). (read)
- **C52**, **C200** and **C235** Done.
  - The only `get_if` is the fold's own
    (`include/idr/Support/Match.h:128`, at cb5cd6fb).
  - A case that takes every type is refused when the compiler is built
    (`:227`).
  - `match(mlir::Type, …)` folds over the generated `DialectTypes`
    (`:298`). The header now says what D126 rules: a type's own facts
    are interface methods, and the fold reads only what no interface
    declares (`:9-13`).
  - (measured: `git grep -nE 'std::get_if|holds_alternative|std::visit\b'
    -- foreign/idr runtime`: 3, all in `Match.h`; read)
- **C53** Partial.
  - The precompiled header is built (`lib/IR/CMakeLists.txt:131-134`;
    `-fno-pch-timestamp` at `CMakeLists.txt:446`; ccache sloppiness at
    `tools/bootstrap.sh:273`).
  - No `-ftime-trace` baseline and no "measured as built" record exist.
    (read, measured)
  - Owner INT. Remaining: on a built toolchain, take the `-ftime-trace`
    header cost per unit with and without the PCH, and record it with
    build and input under `audits/p0/verify/` or in PINS.md (stage 1).
- **C54** Partial.
  - Extensive hardening is on in every configuration
    (`CMakeLists.txt:383`), with the handler at
    `runtime/End/End.cpp:329`.
  - Release's cost is neither measured nor recorded. (read, measured)
  - Owner INT. Remaining: measure the release build with and without
    `_LIBCPP_HARDENING_MODE_EXTENSIVE` on the program suite, and record
    the number (stage 1).
- **C55** Partial (in flight, L16ee for `Translate/*`).
  - The checker side is done:
    - `toCompileCase`, `canInline*`, `inlineSafe` and
      `refersToRuntimeM` have 0 hits, and `PartialEval.idr` and
      `Core/Transform.idr` are gone;
    - recheck 3's `Phase` vestige now carries `TreeFor` beside its
      `RigCount` (`compiler/checker/src/Core/Case/CaseBuilder.idr:52`).
  - Remaining, in two parts:
    1. Case blocks are still translated as definitions of their own,
       named `<parent>.case<k>`
       (`compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr:71-76, 89-96`),
       and no step puts a block's tree into its parent as a region.
       Owner L16. Remaining: emit a `CaseBlock`'s tree in place as a
       region of its parent's match. Then delete `typedBlock`'s case arm
       and the `.case<k>` naming (`Keys.idr:71-76, 167`;
       `Boundary.idr:185, 517, 526`; `State.idr:421`).
    2. `%transform` rules are still elaborated for every method of every
       implementation, though nothing applies them
       (`compiler/checker/src/Idris/Elab/Implementation.idr:298-299,
       542-558`; `TTImp/ProcessTransform.idr`). They are also stored
       (`Core/Context.idr:1359, 2289-2305`) and written to the TTC
       (`Core/Binary.idr:67, 240, 513-517`). Owner L17. Remaining:
       delete `addTransform`, `ProcessTransform.idr`, the `transforms`
       field and its TTC section, and `ITransform`'s elaboration.
  - (read, measured)
- **C56** Partial (in flight, L16ee).
  - The derivation concludes sizes and breadth as well as heights
    (`compiler/src/IdrisMLIR/Proof/Sizes.idr:3-19`;
    `compiler/src/IdrisMLIR/Frontend/Finite.idr:180-197`).
  - The node split's products, which C56 makes conditional on stage 1,
    are unmeasured. (read)
  - Owner L16. Remaining: measure the node split's products at stage 1,
    and split the flow by node only if they are large.
- **C57** Done. No Core dump option or reader remains. (measured)
- **C58** Done. A refusal is an op built from `SomeRule`, indexed by
  category (`compiler/src/IdrisMLIR/Dialect/Idr.idr:37`;
  `spec/Core/Rules.idr:25-82`). `idr.refusals`, `outsideLanguage` and
  `inFlight` have 0 hits. (read, measured)
- **C59** (with D77) Done. The runtime's joined bodies shed
  `probe-stack` (`lib/Driver/LinkRuntime.cpp:81-87`). Clash protection
  is on in the tools, in GMP and in the runtime (`CMakeLists.txt:428-432`;
  `runtime/CMakeLists.txt:154-162`). (read)
- **C60** Done; closes recheck 3's row.
  - The IO test writes past the shipped one-page buffer
    (`tests/io-buffer/run:4-11, 20`; `runtime/Io/Io.h:27`).
  - `IDRIS_RT_IO_BUFFER_SIZE` and the count symbols have 0 hits.
  - (read, measured)
- **C61** Done. snmalloc is a patch project (`tools/patches.sh:29`).
  Patches 94 and 95 are carried, each with its report, check and PINS
  entry (`PINS.md:1313-1323`). (read, measured)
- **C62** Done. Every program symbol takes `programPrefix = "idr."`
  (`include/idr/Conversion/Mangle.h:20`). (read)
- **C63** Done. Frame chunks are given back with one spare kept
  (`runtime/Alloc/Frames.cpp:38-52`). No pressure signal exists.
  (read, measured)
- **C64** (with D94) Done.
  - The rows have one writer, callees first
    (`lib/Transforms/Effects/Writer.cpp:3-9, 72`).
  - Containment is checked on functions and equality on calls
    (`lib/IR/Verify/Program.cpp:203-206`; `lib/IR/Func/Call.cpp:261-262`).
  - `Amount kind = Finite | Unbounded`
    (`spec/Functions/Parameters.idr:66-67`). (read, measured)
- **C65** Partial. This is a new finding: recheck 3 counted C65 done.
  - Done:
    - `idr.join` and `idr.loop` are one family
      (`spec/Control/Joins.idr:75-76, 127-137`);
    - `idr.loop` implements `LoopLikeOpInterface`
      (`include/idr/IR/Generated/IdrOps.td:662-676`);
    - `LoopToJoin` is a rooted rule (`spec/Control/Rules.idr:53`);
    - `Tail/Loop.cpp`, `Tail/WhileDo.cpp` and the `i1` flag are gone.
  - Missing: C65's `idr.may_loop` (0 hits in `foreign/idr` and
    `compiler/spec`).
    - The family declares `Executes [] [] Recursive Untouched`
      (`spec/Control/Joins.idr:136`), so a loop of partial origin
      carries no divergence of its own.
    - Divergence lives only at the function's entry
      (`lib/IR/Func/Rows.cpp:155-163`).
    - The inliner admits every call (`lib/IR/Func/Inliner.cpp:38-40`).
  - So a partial callee's loop, inlined into a proved caller, loses its
    divergence. Where its results go unused, it reads as dead: the
    eager-evaluation divergence C65's marker kept. (read, measured)
  - Owner L09 (`spec/Control/`). Remaining: give the loop member a
    divergence write in code Idris did not prove (C65's `idr.may_loop`
    at each join region's entry), so the row derivation sees it after
    inlining or contification. Otherwise the coordinator records why
    another fact replaces it.
- **C66** Partial, unchanged.
  - The path rule is in place
    (`compiler/checker/src/Core/AutoSearch.idr:44-80, 143-149`).
  - No test holds the discriminator C66 names: `natToFinLT 3 {n = 10}`
    elaborating by search while `Cons2.idr` is refused. Every
    `natToFinLT` in the tree passes its proof explicitly (`git grep -nE
    'Cons2|natToFinLT' -- . ':!proposals' ':!audits' ':!sources'
    ':!third_party'`). (read, measured)
  - Owner L19, with L17. Remaining: add a test whose expected file shows
    `natToFinLT 3 {n = 10}` elaborating with its proof left to search,
    and `Cons2.idr` refused.
- **C67** (with D83) Done. No implementation-choice rule remains among
  the megamorphic rules (`spec/Core/Rules.idr:34-41`). AGENTS.md reads
  as D83 says. (read)
- **C68** Done. Knots, then in-place, then deduplicate, all after
  defunctionalize (`spec/Pipeline/Pipeline.idr:586-589`).
  `EliminateDuplicate` has 0 hits. (read, measured)
- **C69** Done.
  - `io.exit` writes IO, `exit` and `crash`, and takes a `UInt8`
    (`spec/Ops/IO.idr:162-168`).
  - Consumption is `Free` on `Count` alone
    (`spec/Effects/Declaration.idr:300`).
  - `term_setup` and `Scratch` have 0 hits. (read, measured)
- **C70** Done. A declaration is `Definition` or `Executes`
  (`spec/Effects/Declaration.idr:502-506, 590-601`). "Declares nothing"
  is `EffectSet::everything()`
  (`include/idr/IR/Effects/Declared.h:129`). `AcquiresCell` and
  `allocOther` have 0 hits. (read, measured)
- **C71** Done. No pass of ours adopts `LocalAliasAnalysis`, so no
  patch is owed yet. (measured)
- **C72** Done; closes recheck 3's row.
  - `lib/Transforms/Expect/Report.cpp:15-16` names `idr.func` and
    `llvm.func`.
  - The memory table is generated (`spec/Effects/LLVM.idr:123-143`).
  - `noalias` is set at `lib/Conversion/Lower/Functions.cpp:64-85`
    (in flight, 2b-T).
  - `FuncToFunc.cpp` and `mayLoop` are gone. (read, measured)

## C73 to C100

- **C73** (with D98, D103) Done. The pipeline runs no `cse`,
  `canonicalize` or greedy driver (`spec/Pipeline/Pipeline.idr:15-18,
  43-54`). The acquisition law is at `spec/Effects/Declaration.idr:48-49`.
  (read, measured)
- **C74** (with D102) Done. `Termination = Terminates ComponentId |
  Acyclic | MayDiverge (List1 Shown)`
  (`compiler/src/IdrisMLIR/Term.idr:1672`). Emit writes
  `#idr.terminates` (`Emit/Closures.idr:76-80`). `absorb`, `TS.loops`
  and `total' = True` have 0 hits. (read, measured)
- **C75** Done. `Op` is indexed by its group counts, with guards
  `Guard (Fin i)` (`spec/Core/Op.idr:430-455`). Emit's internal errors
  in `Emit/Operations.idr` have 0 hits. (read, measured)
- **C76** Done. Hooks and laws reach C++ as printed tables
  (`include/idr/IR/Generated/Hooks.h.inc`, `Laws.h.inc`). No
  `semilattice()` re-proof remains. (read, measured)
- **C77** Done. The dialect list is the specification's
  (`spec/Core/Dialect.idr:21`). `IdrRules.txt`, `IdrPassRoles.txt` and
  `IdrPassStages.txt` are gone. (read, measured)
- **C78** (with C164) Done (in flight, 2b-S); closes recheck 3's row.
  - The fingerprint hashes the printed value of the outputs
    (`spec/Generator/Main.idr:86-101`), and `generate` is pure
    (`spec/Generator/Outputs.idr:336`).
  - `tests/spec-current` and `tests/spec-self` hold byte identity.
  - `tests/dialects-current` is C229's new check, not the comparison C78
    deleted.
  - The generator's sources are found by a line scan of `spec.ipkg`'s
    text (`Main.idr:33-52`). That is outside C78's text; see the last
    section. (read)
- **C79** Done. `ErasedBinderOpInterface` is at
  `spec/Families/Dialect.idr:296-316`. There is one substitution
  (`include/idr/IR/Families/Substitute.h:3-11`). (read)
- **C80** Partial, unchanged since recheck 3. (read, measured: `git grep
  -n -E 'ListType|IsList' -- compiler/src`)
  - Done:
    - groups are strongly connected components
      (`lib/Transforms/Defunctionalize/Declare.cpp:18-25`);
    - `Promise = None | InPlace` (`spec/Families/Group.idr:43`);
    - `DataRemap`, `SumKind`, `CtorRole`, `KindRule`, `RoleOnce`,
      `ruleOf`, `roleTags` and `BaseListOf` have 0 hits.
  - Remaining:
    - the registry's `ListType` hook
      (`compiler/src/IdrisMLIR/Registry/Entry.idr:331-335`; its doc says
      no handler reads it);
    - `IsList`, written at `:454` and never read (`:407`);
    - the Faster row on `Prelude.Basics.List`, whose comment contradicts
      C80 (`compiler/src/IdrisMLIR/Registry/Faster.idr:105-116`).
  - Owner L16. Remaining: delete the `ListType` constructor, the
    `IsList` case and its write, and the List row with its comment.
    Keep the `pack` and `scalarBytes` rows.
- **C81** Done. A family's member facts are made in its storage
  (`include/idr/IR/Families/FamilyStorage.h:55-91`). `!idr.box`,
  `layout::fit`, `solveHeld` and `holdsNoComponent` have 0 hits.
  (read, measured)
- **C82** Partial (in flight, L16ee), unchanged since recheck 3.
  - Done:
    - `idr.index.assume` (`spec/Families/Declarations.idr:18`) and
      `idr.data.reindex` (`spec/Families/Ops.idr:210-232`);
    - the identity hooks of `replace`-shaped definitions are gone
      (`compiler/src/IdrisMLIR/Registry/Recognized.idr:79, 114, 165`);
    - there is one crash default
      (`Frontend/Translate/Cases.idr:254, 288`).
  - Remaining: an arm Idris proved impossible is still `Dead` and left
    out of the match (`Cases.idr:278-288, 293-296`). `Unreachable`
    carries a location only (`compiler/src/IdrisMLIR/Term.idr:365`).
    (read)
  - Owner L16. Remaining: give `Unreachable` a justification (the
    impossible constructor or the clause marked `impossible`), and keep
    such an arm as a case ending in it instead of dropping it in
    `armsOf`.
- **C83** (with D124) Done. `idr.lend` threads its owner
  (`spec/Lifetimes/Declarations.idr:590-614`). `idr.carrier` is at
  `:616-641`, and its alias check uses `ViewLikeOpInterface`
  (`lib/IR/Lifetimes/Loans.cpp:64`). `Viewing`, `ownersAcross`,
  `backEdges`, `deadness`, `shareIntoCarriers` and `readBare` have
  0 hits. (read, measured)
- **C84** (with D95 and D96) Done (in flight, 2b-S). The frame-limited
  rule is a local verifier rule (`lib/IR/Lifetimes/Proof.cpp:1-16, 36`).
  `lifetime.pack` and `lifetime.unpack` are at
  `spec/Lifetimes/Declarations.idr:788, 815`. (read, measured)
- **C85** (with C208) Done. An element read is a view by its stretch's
  row, and a reference of its own otherwise
  (`include/idr/Analysis/Ownership/Facts.h:287-290`). (read, measured)
- **C86** (with D88 and D90; C144 above) Done. `Hold = Counted Unique |
  Scoped Unique | Static` (`spec/Grades/Hold.idr:41`). `madeStatic`,
  `isStatic`, `persistHeld` and `Phantom` have 0 hits. (read, measured)
- **C87** Partial (in flight, 2b-S for `spec/**`). This is a new finding.
  - Done:
    - a token at quantity many is refused
      (`lib/IR/Counting/Ops.cpp:37-39`);
    - `count.dup` refuses `unique self` (`:100-109`);
    - `lin.use` is gone.
  - Not done: `count.dup`'s operand predicate reads the release only
    (`spec/Counting/Declarations.idr:61-68`; `lib/IR/Counting/Ops.cpp:35`),
    so a dup of a `once, counted` operand verifies by its type.
    - The linearity rule (`lib/IR/Verify/Linearity.cpp:3-6`) still
      allows such a value one use, so no second owner can be built.
    - What C87 asks is that the type refuse it.
  - C87's drop clause reads as superseded by D90, since a `once` value
    is dropped. (read)
  - Owner L07. Remaining: make `count.dup` take a `many, counted`
    operand: a predicate beside `countedValue`, or `CountDupOp::verify`
    refusing `usesOf(value) == Uses::Once`.
- **C88** Done. The frame bound is computed from types
  (`lib/Transforms/Counting/Bound.cpp:3-16`), checked by
  `tests/runtime-frame-bound/run:4-13`. (read)
- **C89** Done (in flight, L16ee). `in_place` is refused as `HookShape`
  on a family that is not one constructor with fields
  (`compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:932-944`). It is
  tested by `tests/hook-in-place-two-constructors`. (read)
- **C90** (with D79) Done. `inPlace` runs right after defunctionalize
  and knots (`spec/Pipeline/Pipeline.idr:561`). Rebuilds are
  `TokenRebuildOp` (`lib/Transforms/InPlace/Sites.cpp:81`). `IdrDemand`
  has 0 hits. (read, measured)
- **C91** Done. `SuccessorSources` and `unknownFrom` are gone
  (`lib/Analysis/Ownership/ExclusivityGraph.cpp:17, 79`), and
  `tests/in-place-crash-case-gives-nothing` exists. (read, measured)
- **C92** (with C173 and C190) Done. `unique::raiseClaims`
  (`include/idr/Transforms/InPlace/Unique.h:1-18, 136`) runs in
  `idr-unique-results` and in `idr-in-place`
  (`lib/Transforms/InPlace/Writer.cpp:158-165`), before bufferization
  (`spec/Pipeline/Pipeline.idr:562`). (read)
- **D110 and D122** (on C90 and C92) Done. Per-member `selfCells` and
  `buffers` are at `include/idr/IR/Families/FamilyStorage.h:65-71`.
  C185's eight refused programs now compile: the `tests/linarray-*` and
  `tests/vec-pop-then-push` expected files hold no refusal. (read,
  measured)
- **C93** Done. Patches 65 to 71 are carried, each with `llvm.patch`, a
  README, a `tests/upstream-early-exit*` check and PINS entries.
  `idr.jump` declares no effects (`spec/Control/Joins.idr:202-217`).
  (measured, read)
- **C94** Done. One conversion with upstream's SCF-to-CF patterns
  (`lib/Conversion/Matches.cpp:374-381`), and no poison yields. (read,
  measured)
- **C95** Done. Contification is a dominator tree with nothing budgeted
  (`lib/Transforms/Optimize/Contify.cpp:13-31`). Case-of-case copies
  only the dispatch (`lib/Transforms/Joins/CaseOfCase.cpp:1-8, 46-60`).
  (read, measured)
- **C96** (with C167, C171 and C176) Done (in flight, 2b-T).
  - Frames are a family indexed by the awaited row
    (`lib/Transforms/Tail/Frames.cpp:5-23`).
  - `idr.dest.answer` is at `spec/Tail/Declarations.idr:117`.
  - `DestType::verify` follows C176 (`lib/IR/Tail/Destinations.cpp:32-43`).
  - `answerTypeOf`, `asAnswer` and `fromAnswer` have 0 hits.
  - (read, measured)
- **C97** (with D96 and C171) Done (in flight, 2b-T; re-read at
  59dcc964). A tail-call operand whose lifetime ends with the call is
  refused (`lib/IR/Tail.cpp:134-158`). (read)
- **C98** Partial, measurement only.
  - The bound is read through `DiagnosticInfoStackSize`
    (`lib/Driver/StackBound.cpp:56`) and recorded in
    `idris_rt_program_built` (`runtime/Start/Entry.cpp:29-37`).
  - The musttail matrix is `tests/musttail-matrix/*.ll`.
  - The margin is unrecorded in every target entry. (read, measured)
  - Owner INT, with L11. Remaining: as C201.
- **C99** Partial, unchanged since recheck 3.
  - Patches 10, 80-85, 88-93 and 97 are carried (`PINS.md:313-332`).
  - `PINS.md:333-340` still leaves the op parser and printer, a dialect
    attribute's parser and printer, and `eraseOp` through
    `std::function` for the stage-1 painting. (read, measured)
  - Owner L06. Remaining: after stage 1's painting, carry one patch per
    remaining family, each with its `tests/upstream-<bug>` and PINS
    entry, or record the measurement that shows it within the stack.
    Then update `PINS.md:333-342`.
- **C100** Done. The heap span is aligned
  (`runtime/Platform/Platform.h:207-211`), with patches 94 and 95
  carried. `heapRegion`, `MAP_NORESERVE`, `ensure_init` and
  `idris_rt_gmp_init` have 0 hits. (read, measured)

## C101 to C130

- **C101** Done; closes recheck 3's row.
  - `idris_rt_exit(uint8_t)` (`runtime/End/End.cpp:317`;
    `runtime/Generated/idris_rt_ops.h:120`), with `TakesUInt8` at
    `spec/Ops/IO.idr:168` (in flight, 2b-S).
  - `Ending = Exited (Fin 256) | Crashed Crash | OutOfMemory`
    (`spec/Runtime/Endings.idr:208-212`).
  - The program's name comes from its record
    (`runtime/Start/Entry.cpp:38`).
  - 93 `expected-ending` files exist.
  - `IDRIS_RT_CRASHED`, `checkStatus`, `idris_rt_crash_str`,
    `idris_rt_main_return`, `idris_rt_io_exit` and `RootKind::Status`
    have 0 hits. (read, measured)
- **C102** Done. `#idr.site` is an attribute
  (`include/idr/IR/Generated/IdrTypes.td:392`). A crash passes the
  cause's enum as an immediate with the site's operands
  (`lib/Conversion/Runtime.cpp:177-189`). The location search is gone.
  (read, measured)
- **C103** Done. The lowest `memory.max` and `memory.swap.max` up the
  path, and v1's `hierarchical_memory_limit`
  (`runtime/Platform/Posix/Cgroups.cpp:279-292, 332`). `LimitRange`
  sits after `StatsRange` (`runtime/Alloc/Cells.cpp:113, 179-180`).
  (read)
- **C104** Done. `proposals/0017-apple-dmp.md:6-11` withdraws D9 and
  P1. (read)
- **C105** Done. A field's `to_tensor restrict` is made writable only
  where the cell claims its own cells
  (`lib/Transforms/Bufferize/Releases.cpp:225-237`). `UseModel`,
  `EnterModel`, `lin.use` and `lin.enter` have 0 hits. (read, measured)
- **C193** (on C105) Done. `LArray` is an `InPlaceType` entry
  (`compiler/src/IdrisMLIR/Registry/Recognized.idr:139`), with no Faster
  row (`git grep -n LArray --
  compiler/src/IdrisMLIR/Registry/Faster.idr`: 0). (read, measured)
- **C106** Done. `merge` writes `tensor.collapse_shape` and
  `expand_shape` (`compiler/src/IdrisMLIR/Emit/Tensors.idr:457-475`),
  and its registry entry is a generating one
  (`Registry/Recognized.idr:115`). (read)
- **C107** (with C250 as corrected) Done.
  - The generating ops reach `lowerToLoopsUsingSCFForOp` in
    idr-ordered-loops (`lib/Transforms/StructureLoops/StructureLoops.cpp:116`).
  - Iterator types are `parallel` only where the region computes
    (`lib/IR/OpsArrayRules.cpp:161`).
  - `Idr_Iteration` and `getIterations` have 0 hits.
  - The element take's test stands by C250's correction (see C250).
  - (read, measured)
- **C180** (on C107) Done. `idr.array.place_copy`
  (`include/idr/IR/Generated/IdrOps.td:971`). (read)
- **C108** Done. `upstream/27-one-shot-tensor-like-copy/` and
  `64-tensor-like-per-instance/` each hold `llvm.patch`, a README and a
  reproducer, with PINS entries (`PINS.md:1139, 1156`) and the checks
  `tests/upstream-one-shot-tensor-like-copy` and
  `tests/upstream-tensor-like-per-instance`. (read, measured)
- **C109** Done; closes recheck 3's two comment rows.
  - `#idr.mutable` (`spec/Arrays/Memory.idr:42`).
  - `ArrayUpdateOp::verifyRegions` refuses an in-place touch in the
    region (`lib/IR/OpsArrays.cpp:127-139`).
  - `ElementUpdateOp` and `idr.world` have 0 hits.
  - "world" no longer appears in `include` or `lib` outside `Generated/`
    (`git grep -niE '\bworlds?\b'`: 0). (read, measured)
- **C110** Done; recheck 3's row is closed by C110's own correction.
  - The `Arithmetic` concept refuses a `bool`-constructible `Truth`
    (`include/idr/IR/Numeric/Domain.h:53-57`).
  - Division and the shifts take `SafeDivisor` and `BelowWidth`
    (`Numeric/Arith.h:48-52`).
  - The checks are exhaustive over 8-bit words (`Numeric/Checks.h:5-12`).
  - The runtime includes the one template
    (`runtime/Big/Arithmetic.cpp` includes `idr/IR/Numeric/Inline.h`).
  - (read)
- **C111** Done; closes recheck 3's row.
  - `nonempty` and `finite` are functions of the template, called by the
    folder (`lib/IR/OpsChecks.cpp:66-80`) and by the lowering
    (`lib/Conversion/Checks.cpp:79, 86`).
  - A `#Fin[n]` is seeded with [0, n-1] (`lib/IR/Ranges.cpp:155-161`).
  - (read)
- **C112** Done. The three builders are one capture family in the
  specification (`spec/Closures/Declarations.idr:11-12, 182`), each
  with `Idr_ResultUsesMax` (`include/idr/IR/Generated/IdrOps.td:2717,
  2738, 2758`). (read)
- **C113** (with C157, C158, C204 and D98) Done (in flight, 2b-S);
  closes recheck 3's row.
  - Meaning is one sum (`spec/Core/Op.idr:241-248`).
  - `Values.idr`'s doc now names `idr.platform.os`
    (`spec/Ops/Values.idr:7`).
  - `nat.pred` (`spec/Ops/Bigs.idr:277`) and `io.unsafe_run`
    (`spec/Ops/IO.idr:197`).
  - The family constants (`quotient`, `isSigned`, `left`) have 0 hits.
  - (read, measured)
- **C204** (on C113) Done. The frontend writes no `scf.index_switch`.
  Only the lowering makes one (`lib/Conversion/Lower/Drops.cpp:222,
  358`; `Lower/Repack.cpp:114`). (measured)
- **C114** Done. `upstream/72-scc-iterator-node-numbers` and
  `74-pass-adaptor-preserved-analyses` are carried, with their checks
  and PINS entries (`PINS.md:695, 727`). `Scc.cpp`, `Vertex` and
  `stronglyConnected` have 0 hits. (read, measured)
- **C115** Done. Transforms are actions; a solve unit is a different
  type that cannot be one (`include/idr/Support/Actions.h:3-14`;
  `include/idr/Analysis/Solver/Trace.h:3-10`). (read)
- **C116** Done; closes recheck 3's rows.
  - `RunDeciding` pairs a decide step with its apply group
    (`spec/Pipeline/Pipeline.idr:182-193`), used for narrow (`:615`).
  - `solver::decided` now has its caller
    (`lib/Transforms/Narrow/Narrow.cpp:89`). (read)
- **C117** Done. One flat solve per root over the component's call
  edges (`lib/Analysis/BindingTimes.cpp:1-7`). The adoption check
  against today's remarks needs a build. (read)
- **C118** Done. Erasure crosses once, from the checker's `eraseArgs`
  (`compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:470-475`). No
  instance of a fact computed on both sides was found in this range,
  apart from the frontend copies named at C23 and C122. (read)
- **C119** (with C195) Done. The `Exclusive` handle has 0 hits. `Token`
  is move-only, with `branch` and an N-arm `rejoin`
  (`include/idr/IR/Quantities.h:44-59, 69, 117`). (read, measured)
- **C120** Done; closes recheck 3's rows.
  - `rewriteIf`, `StageFacts`, `byNameIs`, `provedIs`, `foldCheck`,
    `placeOwned`, `DataRemap`, `RunPipeline` and `forEachNamed` have
    0 hits.
  - `known(bool)` became `knownOf(numeric::Bit)`
    (`lib/IR/OpsChecks.cpp:38-40`).
  - `StagedPass` is CRTP with no virtual
    (`include/idr/IR/IdrDialect.h:165-178`), through
    `upstream/76-pass-base-derived-class`. (read, measured)
- **C121** Done. `audits/p0/design/compile-time-cpp.md:9-20, 85` is
  re-based on the specification. `matchPin` has 0 hits outside the
  audits. (read, measured)
- **C122** Partial (in flight, L16ee), unchanged in substance since
  recheck 3.
  - Done: a definition's erasure is read once, from the checker's
    `eraseArgs` (`Frontend/Translate/Closed.idr:470-482`).
  - Remaining: the fact is held in two types. `ArgumentAt = NoValue |
    RuntimeValue Uses` (`Frontend/Translate/State.idr:864`) mirrors
    `Use = Erased | Used Uses` (`Frontend/Resolve.idr:217`) case for
    case, through `byQuantity` (`Closed.idr:465-468`). The index case
    C122 puts in the position type is still left to each instance.
  - Growth's site walk gives a definition's parameter its stand by the
    binder's quantity (`Frontend/Growth/Sites.idr:2523`, `standFor
    Nothing rig … = byQuantity (use rig)`), beside `argumentAt` at
    `:954` and `:2311`.
  - (read, measured)
  - Owner L16. Remaining: make C122's one position type, `Absent |
    Index Sort | Runtime Quantity ClosedTerm`, the type `argumentAt`
    returns, delete `ArgumentAt` and the second `byQuantity`, and have
    `standFor` read the definition's position through `argumentAt`.
- **C123** Partial (in flight, L16ee).
  - Done:
    - a static argument is one `StaticReading`, which holds its reading
      at quantity 0 with its form, height and head tied to it by type
      (`Frontend/Translate/State.idr:86-98`);
    - `Decided p = Yes (0 _ : p) | No (0 _ : Not p)`
      (`compiler/src/IdrisMLIR/Proof/Growth.idr:51-53`);
    - `TS.readings`, `render` and `closedHeight` have 0 hits as code.
  - Remaining: two comments still name the deleted `closedHeight`
    (`Frontend/Growth/Caps.idr:135, 165`). The decision's literal form
    (`Template Admitted 0` with closed leaves) is not the form the tree
    took. (read, measured)
  - Owner L16 (comments). Remaining: L16 rewrites the two comments, and
    the coordinator records `StaticReading` as C123's one
    representation.
- **C124** Done (in flight, L16ee). Only a `Delay` the elaborator
  inserted moves a `let` (`Frontend/Translate/Closed.idr:335-347`,
  `MkDelaying _ ByElaborator`). (read)
- **C125** Done. The checker has one POSIX path grammar
  (`compiler/checker/src/Libraries/Utils/Path.idr:19-25`). `isWindows`,
  `Volume`, `pathLookup`, `dirSeparator` and `pathSeparator` appear only
  in the README's account of what went (`compiler/checker/README.md:102-106`).
  C233 retired the `upstream/fork-posix-paths` record. (read, measured)
- **C126** Partial, unchanged.
  - Done: `ITypeOrValue` with `Overlaid`
    (`compiler/checker/src/Idris/Desugar.idr:566, 571, 584`) and `Sort =
    Universe | Known | Unknown`
    (`compiler/checker/src/TTImp/Elab/Ambiguity.idr:478`).
  - Missing: the comparison of checked terms with stock Idris's at
    `%ambiguity_depth 1000` (`git grep -n ambiguity_depth -- tests tools
    harness`: 0).
  - The check now sits against AGENTS.md ("There is no oracle"), and
    D118 makes the checker track no upstream. (read, measured)
  - Owner L17, with L19. Remaining: the coordinator records whether
    C126's comparison survives AGENTS.md and D118. If it does, L19
    writes it as a one-time qualification record. If not, C126's check
    sentence is struck.
- **C127** Partial, unchanged since recheck 3 apart from the growth
  case.
  - Done: `retryGuess` refuses a growth at `LastChance` and postpones
    otherwise (`compiler/checker/src/Core/Unify.idr:1532, 1606`).
  - Remaining:
    - `Searched = Found a | Grows Grown` (`Core/Unify.idr:186-188`) has
      no `Repeated` case. A repeated goal fails as an ordinary failure
      (`Core/AutoSearch.idr:696-708`).
    - The quote's depth still travels as the `Error` constructor
      `QuoteTooDeep`, thrown at `Core/Normalise/Quote.idr:196` and
      caught at `:65`, with arms at `Core/Core.idr:204, 413, 533, 624`
      and `Core/Context.idr:1082, 1182`.
  - (read)
  - Owner L17. Remaining: add `Repeated` to `Searched` and return it
    from `abandonIfCycle`'s test instead of throwing `CantSolveGoal`.
    Make the depth-limited quote return `TooDeep` without throwing, and
    delete `QuoteTooDeep` and its arms.
- **C128** Done. `delayDepth`, `deeper`, `search_timeout`,
  `foreign_impl`, `debug-elab-check` and `processTTImpFile` have 0 hits
  in `compiler/checker/src`. `nfThreshold` stays, named
  (`Core/Options.idr:132`). (measured)
- **C129** Done. `CaseBlock : (parent : Name) -> (ordinal : Nat) ->
  Name` (`compiler/checker/src/Core/Name.idr:49`). `outermost` has
  0 hits. `keyOrigin` reads the block off its name with no search
  (`Frontend/Translate/Keys.idr:89-96`).
  - The Idris `pull-request.diff` clause went with C233. All 13
    remaining `pull-request.diff` files are LLVM's or simdutf's.
    `tests/upstream-patches` checks every carried patch.
  - (read, measured)
- **C130** Done.
  - `--idr-expect-at` is in `lib/Driver/Options.cpp:173` and
    `lib/Transforms/Expect/Stages.cpp:3`.
  - The suite turns on `--idr-contracts` for every compilation
    (`harness/Lit.idr:120`; `harness/Programs.idr:250`).
  - `#idr.binder` is an attribute
    (`include/idr/IR/Generated/IdrTypes.td:204`).
  - `harness/lib/mlir.sh`, `checked_steps`, `after:` steps and
    `Quantities.cpp`'s `keyOf` are gone. (read, measured)

## Count

148 rows: 120 Done, 25 Partial, 1 Missing, 2 Superseded, no Regressed,
no Open-owner. One row per decision C1 to C130 (130), and 18 rows for
amendments that add an obligation: C142, C144, C156, C157, C158, C162,
C166, C167 with C203, C180, C186, C193, C196, C201, C204, C236, C250,
C253, and D110 with D122. Every other amendment is read inside its
decision's row (C52's holds C200 and C235, C40's holds C168).

- **Partial (25):** C5, C17, C23, C32, C35, C36, C43, C50, C53, C54,
  C55, C56, C65, C66, C80, C82, C87, C98, C99, C122, C123, C126, C127,
  C156 and C201.
  - Of these, C5, C43, C98, C201, C32, C35, C36, C53, C54, C56, C99 and
    C156 wait on measurements that need stage 1.
- **Missing (1):** C13.
- **Superseded (2):** C47 and C48, by D98.

Closed since recheck 3: C7, C12, C24, C33, C34, C39, C44 (re-read),
C60, C72, C78, C101, C109, C110 (by its correction), C111, C113, C116,
C120 and C144. Recheck 3's Elements row under C39 and C107 is
superseded by C250's correction.

New since recheck 3, in rows it had counted done: C13 (never done),
C65 (`idr.may_loop` missing), C87 (`count.dup` admits a quantity-1
operand by type) and C17 (only a sample is compared).

## Seen outside the range

- `lib/Driver/ReadRuntime.cpp:3-7, 285-291`: a compile accepts either
  runtime kind (`std::variant<Archived, Prepared>`), two read paths
  behind one option.
- `lib/IR/OpsPlatform.cpp:20-29`: `osName` has BSD, Windows and Cygwin
  branches for no target of ours.
- `spec/Functions/Termination.idr:29`: `data Termination` is declared
  and read by nothing, while `include/idr/IR/Func.h:68-82` hand-writes
  the same variant. One fact is held twice (L02, L03).
- `spec/Generator/Main.idr:33-52`: `modulesOf` finds the generator's
  modules by scanning `spec.ipkg`'s text, the shape of AGENTS.md's
  never-line on imports found by splitting text (L03).
- `tests/io-buffer/run:21-25`: when the build records no page size, the
  test prints a message and exits 0, a skip reported as a pass (L19).
- `compiler/src/IdrisMLIR/Encoding/Wire.idr` was last changed by L16's
  hand edits (66838a75, 5d8044cd), though `generated.manifest:63` lists
  it. Only `make check` can say whether specgen still writes it (C78's
  area, INT).
- `audits/bugs.md:11-14`: the status paragraph still describes main at
  b8301ebe (2026-10-21).
