<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Cull plan: what goes, what waits, who deletes it

The synthesis of the nine cull reports in this directory (pipeline,
analyses, verifiers, dialect, runtime, frontend, checker, tests-tools,
deps-patches), read against AGENTS.md's "Delete before you optimize" (the
owner, 2026-10-23: the Elon algorithm, "aggressively cull the old parts")
and "NO FACT KNOWN STATICALLY", deduplicated against each other and against
`audits/p0/rederive/plan.md` (its units U01 to U14 are running; its
carriers' questions are settled by C291 to C295, for the owner's review),
with the proposal's D132, D133, C284, C287, C290 to C295 and
`audits/p0/verify/ownership.json`.

- HEAD at writing: `228e1dad`. Lane attribution of modified files is by
  `git status` at that head, and, where a report named another lane, by the
  hunk (marked "by hunk").
- Ground. Every verdict keeps the ground its report gave (read, measured,
  conjecture). Rechecked here, at 228e1dad: the ownership map's stale
  entries (87, by `os.path.exists` and `glob` over every entry: measured);
  `harness/Universal.idr:253-255` (read); `loadBaselineAnalyses` in
  `Analysis/Ranges.cpp:215` and `Narrow/Copy.cpp:74` (`git grep`:
  measured); `Pipeline.idr` clean and free of idr-constants (`git status`,
  `grep`: measured); the frontend's `--check` readers (`git grep`: only
  `Driver.idr` and `tools/upstream-idris/as-idris`); C284 and C290's diff
  to `OpsClosures.cpp` (read). Nothing was built: no C++ tool runs on this
  machine (LLVM is built on the owner's), and no Idris build was run.
- Line counts are the reports'; where two reports count one deletion it is
  counted once, under the unit that does it.

## 0. Corrections applied

1. **P0 §4's open item 1 (the papers in `sources/`) is not answered.** The
   owner's "keep all the sources" referred to the sources of the
   representation-first guideline document, not to `sources/`. Every
   report read it as `sources/` (pipeline.md:60-63 calls it the answer to
   §4 item 1; deps-patches.md:16-21 and others keep `sources/` on it).
   That reading is withdrawn. No candidate below touches `sources/`, so
   nothing here waits on item 1, which stays open for the owner.
2. **idr-constants is already deleted** (D132, 177aefcc), and C290 (L14ac,
   in flight) rewrites its hand folds over `fold::Where`. Pipeline
   candidate 2 is done; the analyses report's KEEP of `Analysis/Constants`
   is moot. The deps report's evidence that patch 29 is reached cited the
   deleted `Effects/Constants.cpp:179`; patch 29 is still reached, through
   `loadBaselineAnalyses` in `Ranges.cpp:215` and `Narrow/Copy.cpp:74`
   (measured), which PINS.md's entry already names. Patch 77's reach rests
   on Ranges and Narrow, which stay.
3. **Pipeline 7 (delete `PassKind` and `GraphEffect`) against the
   rederivation plan's C8 (generate `GraphEffect` into the pass base).**
   The evidence: `GraphEffect` has no reader (pipeline 7: measured); three
   records disagree with the C++'s hand preservation (`defunctionalize`,
   `inline`, `columns`: read), and `tailLoops` is recorded `Keeps` though
   it deletes calls (ctrl R2: read); the hand `markAnalysesPreserved` calls
   are the copy that is wrong in use, since the call graph is built 8 to 10
   times per compile where nothing changed it (ctrl R2: read). Deleting
   the specification's field leaves the wrong copy and every rebuild in
   place. What a pass does to the program graph is a fact known when the
   compiler is built, and AGENTS.md says such a fact is "a compile-time
   constant, generated from the dialect's Idris specification", that "an
   analysis lives in the analysis manager and survives every pass that
   does not change it", and, of two copies, "generate the second copy from
   the first". So **C8 holds for `GraphEffect`**: the field stays, its four
   wrong records are corrected, and it is generated into `StagedPass` by
   W10, which deletes the hand calls. Pipeline 7's premise ("nothing
   generates them from the spec") describes the defect C8 fixes, not a
   reason to delete. **Pipeline 7 holds for `PassKind`**: its one reader
   is a proof (`Pipeline.idr:189`) that restates the decider's mark the
   generator already reads (`Generator/Cpp.idr:1492-1506`), so it goes
   (unit K04).
4. Found while reconciling (each in §3): pipeline 3 is refuted (the
   harness states `reached` on every compilation); dialect 1 is superseded
   by U11; frontend 7's tensor half is refuted by C284; the dialect
   report's KEEP of the run counting entries yields to runtime 3; pipeline
   4's two halves split between O4 and a KEEP; dialect 11's in-flight
   editor is L05y, not L09; verifiers 3's `Program.cpp` is now held by
   L05y.

---

## 1. Every DELETE and MERGE candidate

Reference style: `pipe N`, `ana X`, `ver N`, `dia N`, `rt N`, `fe N`,
`chk N`, `tt N`, `dep N` (report and candidate number). "Unit" is §4's.
Ground: R read, M measured, C conjecture.

### Pipeline (pipeline.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| pipe 1 | idr-deduplicate (pass, header, spec record, CMake, generated, three comments) | DELETE | C (premise R false; merges unmeasured) | ~510 | L18, L03, INT | K18 | M1; K04, K15 (`Pipeline.idr`); K02 (`Expect.h:29`); U08 (`Symbols.h:76` comment) |
| pipe 2 | idr-constants | DONE | | (~360) | | | D132, 177aefcc |
| pipe 3 | `reached` property | REFUTED, KEEP | R: `Universal.idr:253-255` runs `--idr-expect=holds=reached` on every compilation | 0 | L19 | | |
| pipe 4a | `StageTails`, `tailsAt` ≡ `closuresAt` | COVERED | R | (O4's) | L03, L10 | O4 (C294) | |
| pipe 4b | `tailLayoutsAt` ≡ `edgeHoldsAt` | KEEP pending O4 | R | 0 | L03 | | O4 (§3) |
| pipe 5 | idr-lower-runtime and idr-lower-statics into idr-lower's phase 0 | MERGE | R | ~75 | L21, L03, INT | K15 | U07 (`Lower/Statics.cpp`); L14ac (`Conversion/Lower.cpp`) |
| pipe 6 | stale `ownership.json` entries (35 in the area; 87 in the map) | DELETE | M | 87 | coordinator | K09 | nothing |
| pipe 7a | `PassKind` | DELETE | M | ~10 (+39 arguments) | L03 | K04 | nothing |
| pipe 7b | `GraphEffect` | KEEP, generated into `StagedPass` | R | 0 | L03 | W10 (C8) | |
| pipe 8 | idr-contify's first run | DELETE | C | ~5 | L03, L18 | K18 | M2; K04 |

### Analyses (analyses.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| ana A | `#idr.given_back` and everything keeping it in step | DELETE | M, R | ~399 | L02, L03, L18, L10, L16 (generated), INT | K13 | L14ac (`Settle.cpp`, `lib/IR/CMakeLists.txt`); K03 (`Identities.h`); K04 (`Spec.idr`); regeneration |
| ana B | `summarize`, `SummarizeImpl`, `Lattice` into one join per component | MERGE | R, M | ~248 | L14, L02, L15 | K03 | nothing |
| ana C | `GatedCsr`, gated `mark`, `layOutGuarded`, `Graph` concept, `predecessors` | DELETE | M | ~191 | L14, L15 | K03 | nothing |
| ana D | `Extraction.h`'s `Offsets`, `extract`, `Open`, `Question` | DELETE | M | ~89 | L14 | K03 | nothing |
| ana E | the `ProgramGraph` instantiations of four per-component solves, `FunctionNames` | DELETE | M | ~55 | L14, L02 | K03 | nothing |
| ana F | `Analysis/Inline.h` into `Transforms/Inline.h` | MERGE | M | ~23 | L14, L18 | K03 | nothing |
| ana G | exclusivity's recoverable invariant path, one fatal internal error | MERGE | R | ~16 | L08 | K03 | nothing |
| ana H | `Analysis/Effects.h` placement | KEEP (a move) | R | 0 | L02 | | |

### Verifiers (verifiers.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| ver 1 | `GraphNumbering`, `FunctionNumbering` into `WalkNumbering` | MERGE | R | ~76 | L19 | K02 | nothing |
| ver 2 | `CrashSites.cpp` into the record's row bit | MERGE | R | ~57 | L19, INT | K02 | nothing |
| ver 3 | `Program.cpp`'s `target()`, `globals()`, alloc alignment, strided test | DELETE | R | ~52 | L04, L05 | K11 | L05y (`Verify/Program.cpp`) |
| ver 4 | results-as-given's lost-to-layout branch and `@rejoins` | DELETE | R | ~39 | L19 | K02 | nothing |
| ver 5 | three `repeated()` copies into `regionRuns` | MERGE | R | ~17 | L05, L02 | K03 | nothing |
| ver 6 | universal shapes `Nothing`, `Roots` | DELETE | R | ~6 | L19 | K02 | nothing |
| ver C28 | C28's stage-legality trait does not exist | finding, no cull | R | 0 | L03, INT | with K14 | |

### Dialect (dialect.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| dia 1 | `OpIndex.h.inc` and its generator | SUPERSEDED: U11 makes it the op number of MLIR's property encoding (C14 id 3, id 14) | R | (902 if U11 leaves it unread; U11 holds it) | L03 | U11 | |
| dia 2 | 99 unread generated Idris builders | = fe 1 | | | | K21 | QA |
| dia 3 | `idr.lazy.delay` | DELETE | R | ~133 | L18, L09, L16, INT | K12 | L14ac (`Closures/Declarations.idr`, `OpsClosures.cpp`: C290 rewrites the force's fold); L05y (`FlowOps.cpp`, the `Bodies.idr:751` comment); K04 |
| dia 4 | `idr.io.unsafe_run` | DELETE | R | ~97 | L13, INT | K10 | U04 (`Spec/Ops/IO.idr`) |
| dia 5 | `RuleScope` | DELETE | M | ~85 | L03, INT | K04 | nothing |
| dia 6 | `idr.lifetime.reserve` | DELETE | R | ~84 | L05, L21, INT | K11 | L05y (`Lifetimes.h`, `Lifetimes/Ops.cpp`); U07 (`Lower/Lifetimes.cpp`) |
| dia 7 | twelve unused specification constructors and `Declarations.tables` | DELETE | M | ~80 | L03, with L14, L09, L02, L04, L12 | K04 | nothing (two hunks after L14ac, §4) |
| dia 8 | six op-level hook declarations, `isCellValue` | DELETE | M | ~29 | L04, INT | K12 | L14ac (`Families/Ops.idr`); K04 (`Families/Declarations.idr`) |
| dia 9 | `OpensLifetimeOpInterface` | DELETE | M | ~26 | L05, INT | K11 | L05y (`Lifetimes.h`) |
| dia 10 | `WordOfBigOpInterface` into `BigWordOpInterface` | MERGE | M | ~24 | L13, INT | K10 | L14ac (`Spec/Ops/Bigs.idr`) |
| dia 11 | `tensor.splat` flow model | DELETE | C (an in-flight rewrite may admit a writer) | ~8 | L09 | K12 | L05y (`FlowOps.cpp`, `Flow.h`, by hunk: its `everyElementEdges` rewrite) |

### Runtime (runtime.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| rt 1 | head-of-a-show ops and their runtime functions | DELETE | R (no rule requires it; the guard folds without it); C (no program needs it), deleted either way | ~285 | L13, L11, L19, INT, L16 | K10 | L14ac (`lib/IR/CMakeLists.txt:114`); K07 (marker lines); regeneration |
| rt 2 | the frame stack as a home lifetime (`Frames.cpp`) | MERGE | R (one mechanism); C (cost) | ~115 | L11, L10, L21, L05 | K19 | M3; K15 (`Lower/Statics.cpp`); U04, U05, K07 (`Helpers.idr`) |
| rt 3 | run counting entries `inc_run_*`, `dec_run_*` | DELETE | M | ~110 | L11, INT | K07 | nothing (the `Helpers.idr` hunk after U04, U05) |
| rt 4 | per-file `PIN(runtime-quarantine)` markers | = dep 4's runtime part | M | (77, in dep 4) | L11 | K07 | |
| rt 5 | `incOf`, `decOf` restating the entry table | MERGE into the generated table | R | ~25 | L21, L11, L03 | K15 | U07 (`Conversion/Runtime.cpp`); K07 (rt 3); K04 (`Cpp.idr`) |
| rt 6 | cell kinds no reader tells apart, one kind | MERGE | R | ~25 | L11, L04, L21, L19 | K07 | nothing (the `StaticBytes.cpp` hunk after U07) |
| rt 7 | per-OS `#if`s outside the OS unit | MERGE | R | ~6 | L11 | K07 | nothing |
| rt 8 | `OperandKind::Bool` | DELETE | M | ~6 | L03, L21 | K04 | nothing (the `Conversion/Runtime.cpp` hunk after U07) |
| rt 9 | `idris_rt_flush` export, `Runtime::header()` | DELETE | M | ~3 | L11, L21 | K07 | nothing (the `Runtime.h` hunk after U07) |

### Frontend (frontend.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| fe 1 | two builders of one `idr` op (`Dialect/Idr.idr`, Emit, Types) | QA: (a) MERGE into `specOp`, (b) DELETE the unread | R; 760 M | ~825 (a) / 582 (b) | L16, L03, INT | K21 | the owner on D50; U11; K14; L05y (`Emit/Operations.idr`); L16et (`Translate/Primitives.idr`); W05 (`Types.idr`) |
| fe 2 | Idris copies of C++-only types, attributes and member kinds | DELETE | R; count C | ~380 | L03, L16 | K14 | U11; K04 (`Core/Types.idr`) |
| fe 3 | builtin encoders for every builtin record | DELETE | M | 386 | L03, L16 | K14 | U11 (`idris-mlir-tblgen.cpp`) |
| fe 4 | generated traversals no one reads | DELETE | R, M | 206 | L03, L16 | K14 | U11 |
| fe 5 | `Term.idr`'s `hmap`, `cata`, three aliases | DELETE | M | 78 | L16 | K08 | nothing |
| fe 6 | `ITerm`, `Sort` into `Spec.Families.Terms` | MERGE | R; count C | ~60 | L16, L04 | fold into W05 | L16et; L05y; U11 |
| fe 7 | admitted upstream ops said `FrontendWrites` | DELETE `maxUI`'s admission; `minSI`, `minUI` become `PassesOnly`; tensor joins KEEP (C284) | R, M | ~10 | L13 | K10 | regeneration |
| fe 8 | unused enum helpers in `Syntax/*` | DELETE | M | ~81 | L03, L16 | K14 | U11 (`idris-mlir-tblgen.cpp`) |
| fe 9 | `PrimTy` into the checker's `PrimType` | MERGE | R | ~38 | L16 | fold into W03 | L16er; L16et |
| fe 10 | `Multiplicity` into `Use` | COVERED | | (W03's) | L16 | W03 (mult R9) | |
| fe 11 | `ArrayPrim`, `generatedOperands` (N10) | DELETE | R | 33 | L16 | fold into W03 | L12-1 (N10); L16et |
| fe 12 | `contentHash`, `contentName` (`sameName` is W03's) | DELETE | M | ~10 | L16 | K08 | nothing |
| fe 13 | the growth proof's unwired half | CHAINED with C281 (D46, D68); D133 step 1 already deleted `Proof/{Dictionaries,Primitives}.idr` | M | not counted | L16 | L16et | |
| tt 2 chain | the frontend's `--check` task, whose one reader is `as-idris:109` | DELETE | M | ~10 | L16 | K08 | nothing |

### Checker (checker.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| chk 1 | 293 unreached definitions, two unreached modules | DELETE | M (the trimmed checker typechecks) | 2,854 | L17 | K16 | L17be/bf/bg/bh; recomputed last |
| chk 2 | the elaborator-script runner (`%runElab`, `%macro`, `Reify`) | DELETE | R; hooks C | ~1,690 | L17 | K16 | L17 lanes |
| chk 3 | interface hashing | DELETE | R | ~450 | L17 | K16 | L17 lanes |
| chk 4 | `Core.Metadata` and the parser's decorations | DELETE | R | ~420 | L17, L16 (`Driver.idr:41`) | K16 | L17 lanes; K08 |
| chk 5 | command-line and session remnants | DELETE | R | ~400 | L17, L16 (`Driver.idr:379`) | K16 | L17 lanes; K08 |
| chk 6 | colour and console width | DELETE | R | ~240 | L17, L16 (`Driver.idr:403-404`) | K16 | L17 lanes (`Idris/Package.idr`, held, names the colour option); K08 |
| chk 7 | two renderers of one `Error` | QB | R | 221 (b) / ~3,000 (a) | L17, L16 | K22 | the owner; K16 |
| chk 8 | `Idris.Host` statements no one reads, three trusts | DELETE | M | 212 | L17 | K16 | L17's `Host.idr` rewrite (D133, C288) |
| chk 9 | docstrings kept for one warning | DELETE | R | ~200 | L17 | K16 | L17 lanes |
| chk 10 | code-generator remnants | DELETE | R | ~110 | L17 | K16 | L17 lanes |
| chk 11 | package commands and metadata no one reads | DELETE | R | ~80 | L17 | K16 | L17 lanes |
| chk 12 | hole bookkeeping for the IDE | DELETE | R | ~50 | L17 | K16 | L17 lanes |
| chk 13 | `%name` hints with no reader | DELETE | R | ~35 | L17 | K16 | L17 lanes |
| chk 14 | `%start`'s parse path and `startExpr` | DELETE | R | ~25 | L17 | K16 | L17 lanes |

The checker's KEEPs open to the owner (topic logging under C287, literate
sources, `%transform` under C271) have no DELETE verdict and are not
counted or asked.

### Tests, harness, tools (tests-tools.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| tt 1 | `tests/file-size` | DELETE | R, M | 3,390 | L19 | K01 | nothing |
| tt 2 | `tools/upstream-idris` | DELETE | R, M | 522 | L06, INT | K06 | nothing (the `export IDRIS2_PREFIX` line after M7) |
| tt 3 | `tools/compile-times.sh` and the timing record | DELETE | C (a judgement), settled by rule | 477 | L06, L19 | K06 | nothing |
| tt 4 | `bench/regex-dna` and its smoke files | DELETE | C (a judgement), settled by rule | 703 | L19 | K01 | nothing |
| tt 5 | `tools/bisect.sh` | DELETE | C (a judgement), settled by rule | 198 | L06 | K06 | nothing |
| tt 6 | the CMake configure gate | MERGE into `verify-pins.sh` | C, settled by rule | 180 | INT, L06, L19 | K06 (PINS lines in K05) | nothing |
| tt 7 | `tests/build-preset`, `tests/commands` | DELETE | C, settled by rule | 180 | L19 | K01 | nothing |
| tt 8 | `tools/lanes` | DELETE | R | 116 | L06 | K06 | nothing |
| tt 9 | `Trace.idr`'s `--trace-totals`, `--trace-units` | DELETE | M | 65 | L19 | K01 | nothing |
| tt 10 | `harness/templates` | DELETE | R | 52 | L19 | K01 | nothing |
| tt 11 | `tests/scale-threads` into Determinism | MERGE | C | 46 | L19 | K17 | M4 |
| tt 12 | `tests/bench-records` | DELETE | R | 28 | L19 | K01 | nothing |
| tt 13 | `expect-table-current`, `--expect-table` into specgen | MERGE | R | 28 (+351 moved) | L19, L03 | K17 | K02; K04; regeneration |
| tt 14 | `--rules`, `--rule-category` | DELETE | M | 18 | L19 | K17 | U12 (`harness/Facts.idr`) |
| tt 15 | `tests/determinism-threads-rbtree` | DELETE | R | 17 | L19 | K01 | nothing |

### Dependencies and patches (deps-patches.md)

| Ref | Candidate | Verdict | Ground | Lines | Owner | Unit | Waits on |
|---|---|---|---|---|---|---|---|
| dep 1 | Idris reports holding no patch (18, 20, 21, 50 to 55, 59) | DELETE | R | 1,596 | L06, with L19, L17 | K05 | nothing (checker README hunk after L17; `harness/Fuzz.idr:31` comment in K17) |
| dep 2 | status and symptom held three times | MERGE into each report | R (299); C (381 symptom lines, a reading per entry) | 299 (+≤381) | L06 | K05 | nothing |
| dep 3 | `tests/upstream-*` of eleven uncarried reports | DELETE | R | 321 | L19, L06 | K01 (tests), K05 (README) | nothing |
| dep 4 | `PIN()` markers, `tests/pin-sites`, seven cpp-starter entries | DELETE | R | 255 (77 in K07) | L11, INT, L06, L19 | K05, K06, K07 | nothing |
| dep 5 | retired history in PINS.md and upstream/README.md | DELETE | R | 129 | L06 | K05 | nothing |
| dep 6 | the licence machinery for ports (C10) | DELETE | M | 60 | L06, L19, coordinator | K05 | nothing |
| dep 7 | patch 76 (documentation only): stop carrying | DELETE | R | 49 | L06, L19 | K05 | nothing; takes effect at the next toolchain build |
| dep 8 | patch 97 (reached only by another patch's test): stop carrying | DELETE | R (reach), C (no planned writer) | 49 | L06, L19 | K05 | nothing; next toolchain build |
| dep 9 | patch 10 (builtin nesting our IR lacks): stop carrying | DELETE | C | 27 | L06, L19 | K20 | M6 |
| dep 10 | `libs/mlir-hash` into `compiler/src` | MERGE | R | 20 | L20, L16, INT, L06 | fold into W03 | L16er (`Registry/Libraries.idr`, `tools/self.sh`); L17 (`compiler/idris-mlir.ipkg`) |
| dep 11 | Idris patches 104, 105 | DELETE if unreached | C | ≤575 | L06 | K20 | M5 |

### Covered elsewhere, not counted here

- dia 1 (U11), pipe 4a (O4, C294), fe 10 and fe 12's `sameName` (W03),
  pipe 2 (D132).
- The rederivation's W07 lists `LazyForceOp::fold`'s use test (C2); dia 3
  deletes the whole fold, whose only case is a force of a delay. W07
  drops the item if K12 lands first; if C290 gives the force's fold a new
  case, dia 3 deletes only the delay case.
- The verifiers' KEEP of `cycle-divergence-kept` is deleted by O2 (C292).
- The verifiers' survivor `Local.cpp:132-143` (a second inference) is
  shar 5, in W06. Pipeline 5's own survivor (a static datum's global
  found by digest) is id 6, in U07.
- Frontend 2's `GivenBackEntryAttr` and `GivenBackAttr` go with ana A.

---

## 2. What needs a measurement before it goes

AGENTS.md: "Never: a removal resting on an unmeasured claim (16005000)".
Each conjecture verdict whose claim a number can settle:

| Measure | Candidate | What to measure | Where | What follows |
|---|---|---|---|---|
| M1 | pipe 1 | `numMerged` (`-mlir-pass-statistics`, the harness's Scale report) summed over the program suite and `bench/` at HEAD | the owner's machine (the C++ pipeline) | Deleted either way. Zero or a handful: the pass goes. Many: the pass goes and the merge moves to where the instance key is made (`Translate/Instances.idr`), a new item for L16. |
| M2 | pipe 8 | `numContified` of the first contify run (step 5 of `Pipeline.h.inc`) over the program suite; with that run removed, the second run's `numContified` and the specializer's `numNodes` | the owner's machine | The run goes if its count is 0, or if the second run's count rises by as much with no growth in `numNodes`. Otherwise it stays (C45's two runs). |
| M3 | rt 2 | frame push and pop cost: a program whose cycles push frames on every call (a deep non-tail recursion across a cycle), timed before and after on arm64 macOS and x86_64 Linux | the owner's machine | Merged either way: if the home bump is slower, the lifetime chain's bump takes the frame path's fast case, so one mechanism stays. |
| M4 | tt 11 | functions per thread at 13 threads on `bench/rbtree` against the scale `functions` fixture | the owner's machine (Determinism compiles programs) | Merged either way: if rbtree's split is narrower, a `determinism` call over the scale fixture replaces the test. |
| M5 | dep 11 | bootstrap the stock Idris at 89ba32eb with the series minus 104, then minus 105, and build stage 0 (checker, frontend, specification, `libs/`, harness) | this machine (no LLVM; stage 0's checker typecheck took 3,034 s here) | Each unreached patch goes with its test and entry; a reached one stays, with the site it reaches written into its `sites:`, which names none today. |
| M6 | dep 9 | `idris-mlir-opt` parsing and printing a deep tree constant (`#idr.con` through cell arrays, 10,000 deep) on the tools' small stack, with and without patch 10 | the owner's machine (LLVM) | Unreached: stop carrying, report kept as a submission, D33 untouched. Reached only through our own attribute parser: patch 10 goes anyway (it does not cover that path) and the recursion is ours to fix, under D33. |
| M7 | tt 2's chain | `make check` and `make test` without `export IDRIS2_PREFIX` | `make test` on the owner's machine | Both pass: the line goes and `tests/idris-environment/expected:2` follows. |

Conjecture verdicts that need no measurement, because no number changes
what goes: rt 1 (no rule requires the rewrite; how often it fires does not
make one), dep 8 (the reach is read: 0 writers of MLIR bytecode), dep 2's
symptom lines (a reading of each entry against its README, done in K05),
dia 11 (a question to L05y, not a number), and the judgements tt 3, tt 4,
tt 5, tt 6, tt 7 (§3).

---

## 3. Decisions

### The owner's questions

Two candidates remove something an owner's ruling requires or change a
promise to users. Each is asked alone, in this order, with the next held
until the first is settled.

**QA. D50: builders of the ops with no attribute and no region.** D50
(the owner, 2026-10-21) kept builders printed, "each a plain function
typed by its op's operand count", because "a generic builder's type would
depend on a run-time value of varying representation, which the subset
refuses". Since then `specOp` (`Emit/Operations.idr:138-139`) builds any
op with no attribute and no region from its specification value, typed by
the op value's own indices, and both hosts build it. Of 166 printed
builders, 96 have no reader and 29 more duplicate `specOp` (measured).

- (a) Amend D50 for those ops: print a builder only for an op with an
  attribute, a region or a variadic group; the 29 calls become `specOp`;
  Emit's `shiftOp` and Types' `Shift`, `Numeric` and per-category `Prim`
  constructors become specification values. Buys about 825 lines (760
  measured), one way to build an op, and a criterion that cannot drift.
  Costs D50's text; L16 rewrites 29 call sites and the enum layer, after
  L05y, U11 and L16et. Paid by L16 and L03.
- (b) Keep D50: our ops gain the `writer` field the admitted ops carry,
  and the generator prints builders only for `FrontendWrites`. Buys 582
  lines and D50 as written. Costs a flag on every op kept by hand, which
  is already wrong on the admitted ops (fe 7), and two ways to build one
  op. Paid by L03 (a field on every op) and L16.

Recommendation: (a). D50's premise no longer holds in the tree, and the
structural criterion is the one that cannot disagree with what Emit does.

**QB. The checker's one renderer of `Error`.** `Core.Core`'s `showError`
(221 lines) writes every refusal of a compiled program; `Idris.Error`'s
`perror` chain (about 3,000 lines with what only it reaches) prints
package builds and internal errors and decides `failing "msg"` blocks,
which user code reaches. One sum is rendered by two switches. The surviving
text is what users read and what `failing` matches.

- (a) Keep `showError`, delete the `perror` chain: about 3,000 lines. Costs:
  `failing "msg"` matches `show`'s text, so a block upstream rejects can
  pass ours where `show`'s text holds `msg`, a contradiction of
  upstream's `failing`; package builds lose upstream's source excerpts.
  Paid by every user of `failing`.
- (b) Keep `perror`, route the frontend's refusals through the host
  (`host.emitError`): 221 lines. Costs: the refusal texts of compiled
  programs change; the 16 refused-program tests' `-- message:` substrings
  are rechecked (L19). `failing` keeps the text of upstream's renderer.
  Paid by L16, L17, L19.

Recommendation: (b). AGENTS.md: "we must never change the meaning of
upstream concepts", and `failing` is one; the lines (a) saves do not
outweigh a contradiction.

### Settled by AGENTS.md's rules (the coordinator records each, open to the owner's review)

- **pipe 7**: §0 item 3 (C8 for `GraphEffect`; "Delete before you
  optimize" for `PassKind`).
- **pipe 3 refuted**: the harness states `reached` on every compilation
  (read), so the property has its test. The verifiers' survivor (check it
  in `ContractInstrumentation`, dropping a process per compilation) is a
  simplification, not counted.
- **pipe 4b, KEEP pending O4**: verifiers' Brooks argument against
  pipeline 4's merge holds on the evidence: `edgeHoldsAt`'s doc names two
  causes (the frontend's static data and fresh values' claims, and the
  specializer's keying), `tailLayoutsAt`'s one, and C291 now changes the
  first cause and not the second. Under C294 a tail call is a terminator,
  and if O4 leaves `tailLayoutsAt` no reader the column goes then.
- **dia 1 superseded**: U11 gives `OpIndex` its reader (C14 id 14); if
  U11 does not, U11 deletes it, holding the file.
- **dia 3, dia 4, dia 6**: "Delete before you optimize". C112 and C3 rule
  on what `delay` is if written, not that it be written. C113's line
  naming `io.unsafe_run` is amended: D20's forged world and derived row
  hold the fact. C146 and C160 are amended: the decide step makes a
  cursor-to-room call unrepresentable (`Lifetimes/Decide.cpp:196-212`).
- **rt 3 over the dialect report's KEEP**: no reader (measured); L07 §2.8
  is a design, not a ruling, and a run entry returns only with its
  reader. The coordinator strikes "counts over runs of slots" from the
  proposal's summary and L07 §2.8's runtime row.
- **rt 2**: D31 asks for "one stack per result type", which `Frames.cpp`'s
  one set of globals is not and a home lifetime per frame family is; "one
  thing, one representation". Lands after M3.
- **fe 7**: C284 (2026-10-23) admits `tensor.concat` and `tensor.pad` for
  arrays of words, so the tensor half is KEEP; `maxUI` has no writer and
  loses its admission; `minSI` (written by upstream's `LowerAffine`) and
  `minUI` (`Narrow/Copy.cpp`) become `PassesOnly`.
- **fe 2**: types, attributes and family member kinds gain their legal
  stages, as ops have (C28), and the generator prints the frontend's sums
  from those legal at `Higher`; C28's missing trait (ver C28) checks them,
  and `Program.cpp:199-200` goes when it lands.
- **fe 3**: D51's own rule (print "for the ops the specification admits
  alone"), with the admission extended to builtin types and attributes.
- **fe 6, fe 9**: "one thing, one representation". The registry may import
  the checker's leaf `Core.TT.Primitive`: its independence from the
  checker is a design choice, not a rule (read). The spec's `Term` is
  instantiated with the frontend's literal in W05.
- **chk 2**: the strict subset; the profile already refuses `%runElab`
  and `%macro` as outside the language (`Profile.idr:176-177`), and C287
  admits only pragmas whose whole meaning is elaboration. Today a user's
  script runs, `WriteFile` included, before the refusal; the refusal moves
  to the parser.
- **tt 3, tt 5**: no caller, no rule, no test that can fail; a tool that
  reads rows by pass name is the brittle shape AGENTS.md forbids in tests.
  For review: the owner values measurement tools; `--mlir-timing` and
  `tests/pipeline-timing` keep the per-run figure.
- **tt 4, tt 7, tt 15, tt 12**: testing-by-search and "Tests check
  behaviour". The parser workloads stay.
- **tt 6 and dep 4's seven entries**: AGENTS.md scopes PINS.md to "every
  deliberate deviation from [upstream's layout and conventions] and every
  pinned workaround"; "a copy kept in step by a verifier is still a
  copy"; comments do not cite documents. `verify-pins.sh` holds the
  configure gate's fact more strongly. For review: the profile came from
  the owner's bjornpagen/cpp-starter, which no ruling names.
- **tt 8**: the "main only" line goes with `tools/lanes`; the swarm's
  packet states how lanes work.
- **dep 7, dep 8**: AGENTS.md's patch rule ("a patch goes ... when nothing
  in the tree reaches the bug any more, its report kept as a
  submission"). A documentation diff changes no built file; C99's family
  list assumed a reach of MLIR's bytecode writer the tree does not have.
- **dep 9**: D33 stands; the patch goes only on M6.
- **ana A**: C18 amended: the fact is the optimizer's alone. **ana B, C,
  D**: C34's and C15's text recorded as departed from (no second client).
- **ver 3**: "the one place the target is decided"; upstream's converter
  refuses a non-strided layout; `bufferAlignment = 0` leaves no producer
  of the alignments tested.

### Not asked

- `idr.call`'s copy of its callee's `lives_in` (dialect.md, "owner-level"):
  no candidate verdict; whether a pass reads a call alone needs evidence
  first.
- `libs/mlir-relational` (D44's reading), topic logging, literate sources,
  `%transform`: KEEPs in their reports, no deletion proposed.

---

## 4. Dispatch

### Who holds what now (git status at 228e1dad)

| Holder | Files a cull unit meets |
|---|---|
| L05y (C286) | `Emit/{Bodies,Monad,Operations,Tensors,Index}.idr`; `Spec/Grades/*`; `Verify/{Local,Program}.cpp`; `Lifetimes.h`, `Lifetimes/Ops.cpp`; `Flow.h`, `FlowEdges.*`, `FlowOps.cpp`; `OpsCon*.cpp`, `OpsArrays.cpp`; `Families.h`, `Families/{Refinement,Repacks}.cpp`; `Counting/*`; `Bufferize/Reindex.cpp`; `Specialize/Open.cpp`; `InPlace/Unique.*`; the shared manifest |
| L14ac (D132, C290) | `EGraph/*`, `EGraph.h`, `Engine.h`; `Settle.cpp`; `Conversion/Lower.cpp`; `Specialize/Requests.cpp`, `SpecializeState.h` (by hunk); C290's `Spec/Closures/Declarations.idr`, `Spec/Core/Hooks.idr`, `Spec/Families/Ops.idr`, `Spec/Ops/{Bigs,Values}.idr`, `OpsClosures.cpp`, `OpsBigs.cpp`, `OpsPlatform.cpp`, `ConAttr.cpp`, `Constants.cpp`, `Fold.h`, `FoldParts.h`, `Ops/Folds.h`, `Fold/Parts.cpp`, `IdrDialect.h`, `lib/IR/CMakeLists.txt`; the shared manifest |
| L16et | `Frontend/Translate/*` (new `Annotated.idr`), `Growth/*` |
| L16er | `Frontend/Profile.idr`, `Registry/Libraries.idr`, `tools/self.sh` |
| L17be/bf/bg/bh | 29 files of `compiler/checker/`, its README; `compiler/idris-mlir.ipkg`, `Proof/{Covers,Requests}.idr`, the deleted `Proof/{Dictionaries,Primitives}.idr`; `upstream/111-*` |
| U01 to U14 | as `audits/p0/rederive/plan.md` §4: U01 Ranges and Narrow; U02 `Matches.*`; U03 `Consumer.cpp`, `Specialize.h`; U04 `Spec/Ops/{IO,Checks}.idr`, `RuntimeCalls.cpp`, the runtime's exit helper, `Endings.idr`; U05 `Counting/{Expand,ReuseAssign}.cpp`, `Lower/Counting.cpp`, the runtime's token helper; U06 `Fold/Scope.cpp`; U07 `Conversion/{StaticData,StaticNames,StaticBytes,Runtime}.cpp`, `StaticData.h`, `Lower/{Statics,Accounts,Lifetimes,Values}.cpp`; U08 `DataNormal.cpp`, `Types.cpp`, `ContentNames.cpp`, `Symbols.*`, `FamilyStorage.h`, `Spec/Families/Types.idr`; U09 `LabelSites.cpp` and a new test; U10 `Trmc.cpp`; U11 `Generator/Idris.idr`, `idris-mlir-tblgen.cpp`, `MLIR.idr`, `MLIR/Bytecode.idr`, generated `Dialect/*` and `Encoding/*`, `SyntaxSamples.idr`, `OpIndex.h.inc`, `Emit/Index.idr`'s `typeIn`; U12 `harness/{Facts,Programs,Fuzz,FuzzRun}.idr`, `Expect/Quantities.cpp`; U13 `Driver/{Run,LinkRuntime}.cpp`; U14 `Schedules.cpp`, `Transforms/Pipeline.cpp` |

Rules every unit keeps. A unit that changes the specification starts now
and lands its regeneration through INT after L05y, L14ac and U11, which
hold the manifest and the Idris generator. A "hunk after X" caveat is a
hunk of the unit that waits on X while the rest goes. No C++ unit can be
built here; each says what it could not run, and the cutover is built
whole on the owner's machine. Every dispatch packet carries
representation-first and testing-by-search, and every handoff names, per
candidate, the state made unrepresentable, the check moved or the branch
deleted.

### Units that wait on nothing (start now; write paths disjoint from each other and from every lane above)

| Unit | Candidates | Files | Owner | Lines |
|---|---|---|---|---|
| K01 | tt 1, tt 4, tt 7, tt 9, tt 10, tt 12, tt 15; dep 3's tests; fixes: `bench-smoke`'s five missing json inputs, `tests/arity-raising/Main.idr:5-7`'s stale world comment | `tests/{file-size, build-preset, commands, bench-records, determinism-threads-rbtree, bench-smoke, arity-raising}`, the eleven `tests/upstream-*` of dep 3; `bench/regex-dna`, `bench/README.md`; `harness/{Trace.idr, Main.idr, README.md, templates/}` | L19 | ~4,756 |
| K02 | ver 1, ver 2, ver 4, ver 6 | `Transforms/Expect.h`; `Expect/{Cycles,Reached,Allocation,ConstantStack,CrashSites,Tails,Lookup}.cpp`; `Contracts/Contracts.cpp`; `lib/Transforms/CMakeLists.txt:620`; `harness/Properties.idr`; `ExpectProperties.inc`; `tests/{expect-call-results, expect-table-current}` | L19, INT | ~178 |
| K03 | ana B, ana C, ana D, ana E, ana F, ana G, ver 5 | `Analysis/Solver/{Summarize,SummarizeImpl,Lattice,Graph,Mark,Extraction,Schedule,Trace,ProgramGraph,IdentityRecords}.h`, `Solver/Graph.cpp`; `Analysis/{BindingTimes,Identities,Inline,Ownership,Effects}.h`, `BindingTimes.cpp`, `Identities.cpp`, `IdentitiesRecord.cpp`; `Analysis/Ownership/Exclusivity*.{cpp,h}`; `Transforms/{Effects,Inline}.h`, `Effects/{Writer,Component}.cpp`, `Inline/Inline.cpp`, `Ownership/Exclusive.cpp`; `IR/Verify/Linearity.cpp`, `IR/Lifetimes/Verify.cpp`, `Transforms/Lifetimes/Read.cpp`, `IR/Func/Fold.cpp`, one new IR header; `unittests/Refusals.cpp` | L14, with L02, L05, L08, L15, L18 | ~639 |
| K04 | pipe 7a, dia 5, dia 7, rt 8 | `Spec/Pipeline/{Pass,Pipeline}.idr`; `Spec/Core/{Rules,Enums,Types,Op,Rewrite,Interfaces,Declarations,Ods}.idr`; `Spec.idr`; `Spec/Generator/{Ods,Cpp,Outputs}.idr`; `Spec/Functions/{Parameters,LivesIn}.idr`; `Spec/Control/Flow.idr`; `Spec/Families/Declarations.idr`; `Spec/Arrays/Declarations.idr` | L03, with L14, L09, L02, L04, L12, L21 | ~181 |
| K05 | dep 1, dep 2, dep 3's README lines, dep 4 (all but the runtime and CMake markers), dep 5, dep 6, dep 7, dep 8; tt 6's PINS lines; the licence script's other failures | `upstream/**`; `PINS.md`; `LICENSE`, `NOTICE`, `LICENSES/THIRD-PARTY.md`; `tools/licenses.sh`; `tools/bootstrap.sh:1514, 1543`; `tests/{pin-sites, licenses, upstream-pass-base-derived-class, upstream-bytecode-numbering-iterative, upstream-bytecode-deferred-quadratic, upstream-elaboration-primitive-folding}`; `harness/Sem.idr:189` | L06, with L19, coordinator | ~2,360 (+≤381) |
| K06 | tt 2, tt 3, tt 5, tt 6, tt 8; dep 4's CMake marker clauses; fixes: `CMakePresets.json:25`, `tools/toolchain.sh:3-6` | `tools/{upstream-idris/, compile-times.sh, bisect.sh, lanes/, toolchain.sh}`; `Makefile:126-129`; `CMakeLists.txt`; `CMakePresets.json`; `toolchain.lock.json`; `harness/{Lock.idr, Harness.idr}`; `tests/{configure-gate, lock}` | L06, with INT, L19 | ~1,493 |
| K07 | rt 3, rt 6, rt 7, rt 9; dep 4's runtime markers (rt 4); fix: `harness/prop/runtime.h:58` passes six arguments to a five-argument `idris_rt_run_on_stack` | `runtime/**` (every source's marker line; `Rc/Counting.cpp`, `idris_rt.h`, `Io/Output.cpp`, `Platform/**`, `Strings/{Strings,Simd}.h`, `Big/Operands.cpp`, `CMakeLists.txt:12, 25`); `Spec/Runtime/Helpers.idr`; `IR/Layout/{CellInfo,Layouts}.cpp`, `IR/Layout.h`; `tests/{runtime-api, big-cell}`; `harness/prop/{bigmodel,runtime}.h` | L11, with L04, L19 | ~221 |
| K08 | fe 5, fe 12, tt 2's `--check` chain | `compiler/src/IdrisMLIR/{Term.idr, Ids.idr, Frontend/Driver.idr}` | L16 | ~98 |
| K09 | pipe 6 | `audits/p0/verify/ownership.json` | coordinator | 87 |

About 10,010 lines. Caveats, each a hunk that waits while the rest goes:

- K02: if U12's quantities-kept fix edits `Contracts.cpp` or `Expect.h`,
  K02's hunks there land after U12.
- K04: `Spec/Core/Hooks.idr`'s `OnAttribute`, and `PowerOfTwo`'s C++ case
  (`EGraph.h:98`, `EGraph/Rules.cpp:381-384`), after L14ac;
  `Conversion/Runtime.cpp:37-38, 131` (`TakesBool`) after U07.
- K05: `compiler/checker/README.md:602, 667` after L17; dep 7 and dep 8
  take effect at the next toolchain build on the owner's machine.
- K07: `Helpers.idr`'s run entries after U04 and U05 (the exit and token
  helpers live in that file); the marker lines of the runtime files U04
  and U05 edit after them; `Conversion/StaticBytes.cpp:88, 126` and
  `Conversion/Runtime.h:87` after U07.
- K08 lands before W05 starts (W05 holds `Term.idr` and `Ids.idr`).

### Units that wait on a running lane

| Unit | Candidates | Files | Owner | Waits on | Lines |
|---|---|---|---|---|---|
| K10 | dia 4, dia 10, rt 1, fe 7 | `Spec/Ops/{IO,Bigs,Scalars,Rewrites,Shapes}.idr`; `IR/Ops/IO.cpp`; `Conversion/Scalars.cpp`; `IR/OpsScalars.cpp`; `lib/IR/CMakeLists.txt:114`; `runtime/Strings/Show.cpp`, `runtime/Doubles/Printing.cpp`; `tests/{runtime-text, runtime-doubles}` | L13, with L11, L19, INT | U04; L14ac; K07 | ~416 |
| K11 | dia 6, dia 9, ver 3 | `Spec/Lifetimes/Declarations.idr`; `IR/Lifetimes/{Ops,Proof,Kind}.cpp`; `IR/Lifetimes.h`; `Conversion/Lower/Lifetimes.cpp`; `IR/Verify/Program.cpp`; `IR/Verify.h` | L05, with L04, L21 | L05y; U07 | ~162 |
| K12 | dia 3, dia 8, dia 11 | `Spec/Closures/Declarations.idr`; `IR/OpsClosures.cpp`; `IR/FlowOps.cpp`; `IR/Flow.h`; `Defunctionalize/{Edits,Indices}.cpp`, `Defunctionalize.h`; the `Emit/Bodies.idr:751` comment; `Spec/Families/{Declarations,Ops}.idr` | L18, with L09, L04 | L14ac; L05y; K04 | ~170 |
| K13 | ana A | `IR/Func/{GivenBack,Verifier,Edits,Call,Func}.cpp`, `IR/Func.h`; `Optimize/Settle.cpp`; `Tail/{Jumps,Outline}.cpp`; `Spec/Functions/{GivenBack,Declarations,Extents}.idr`, `Spec.idr`, `spec.ipkg`, `Generator/Package.idr`; `Analysis/Identities.h` (comment); `lib/IR/CMakeLists.txt:71` | L02, with L03, L18, L10, INT | L14ac; K03; K04 | ~399 |
| K14 | fe 2, fe 3, fe 4, fe 8 (offered to U11's lane as a fold-in) | `Spec/Core/{Types,Admitted}.idr`; `Spec/Generator/Idris.idr`; `idris-mlir-tblgen.cpp`; `Encoding/*`, `Syntax/*`, `MLIR/Bytecode.idr`, `SyntaxSamples.idr` | L03, with L16 | U11; K04 | ~1,053 |
| K15 | pipe 5, rt 5 | `Spec/Pipeline/Pipeline.idr`; `Conversion/Lower/{Declarations,Statics}.cpp`; `Conversion/Lower.cpp`; `Conversion/Runtime.cpp`; `Spec/Generator/Cpp.idr` | L21, with L03, L11 | U07; L14ac; K07; K04 | ~100 |
| K16 | chk 1 to chk 6, chk 8 to chk 14 | `compiler/checker/**` (with `known/Vocabulary.idr` and the generated `Core/Name/Known.idr`); `Frontend/Driver.idr:41, 379, 403-404`; a refused-program test for `%runElab` | L17, with L16 | L17be/bf/bg/bh; K08. chk 1 last, recomputed on the landed tree | ~6,766 |
| K17 | tt 13, tt 14 (and tt 11 after M4); dep 1's `harness/Fuzz.idr:31` comment; `tests/rules-covered`'s three stale mentions | `harness/{Main.idr, Facts.idr, Fuzz.idr, lib/harness.sh, Properties.idr}` (into `compiler/spec`); `Spec/Generator/Outputs.idr`; `tests/{rules-covered, expect-table-current, zones, scale-threads}` | L19, with L03 | U12; K01; K02; K04; regeneration | ~46 (+46) |
| W03 fold-in | fe 9, fe 11 (after N10), dep 10 | `Registry/{Entry,Libraries}.idr`, `Resolve.idr`; `libs/mlir-hash`, the ipkgs, `Makefile`, `tools/self.sh` | L16, with L20, INT, L06 | W03's own (L16er); L17 (`idris-mlir.ipkg`); L12-1 | ~91 |
| W05 fold-in | fe 6 | `Types.idr`, `Term.idr`, `Emit/Index.idr` | L16, with L04 | W05's own (L05y, U11, L16et) | ~60 |

About 9,260 lines.

### Units that wait on a measurement

| Unit | Candidates | Files | Owner | Waits on | Lines |
|---|---|---|---|---|---|
| K18 | pipe 1, pipe 8 | `Transforms/Deduplicate/`, `Deduplicate.h`; `Spec/Pipeline/Pipeline.idr`; `lib/Transforms/CMakeLists.txt`; `Transforms/Pipeline.h:26`; comments at `Expect.h:29`, `Expect/Named.cpp:7`, `IR/Symbols.h:76`; generated records | L18, with L03, INT | M1, M2; K04, K15; K02; U08 | ~515 |
| K19 | rt 2 | `runtime/Alloc/{Frames,Arenas}.cpp`, `runtime/CMakeLists.txt:67`; `Spec/Runtime/Helpers.idr`; `Conversion/Cells.cpp`; `Conversion/Lower/{Drops,Statics}.cpp` | L11, with L10, L21, L05 | M3; K15; K07; U04, U05 | ~115 |
| K20 | dep 9, dep 11 | `upstream/{10,104,105}-*`; PINS.md's entries and `mlir-recursion`'s `(10)`; `tests/upstream-{recursive-attribute-parser, coverage-repeated-split, case-tree-fallthrough-copies}` | L06, with L19 | M5, M6; K05 | ≤602 |
| (K17) | tt 11 | `tests/scale-threads`, a Determinism call | L19 | M4 | 46 |

About 1,280 lines.

### Units that wait on the owner

| Unit | Question | Candidates | Files | Also waits on | Lines |
|---|---|---|---|---|---|
| K21 | QA | fe 1 = dia 2 | `Spec/Generator/Idris.idr`; `Dialect/Idr.idr` (regenerated); `Emit/Operations.idr`; `Types.idr`; `Translate/Primitives.idr` | U11, K14; L05y; L16et; with W05 (`Types.idr`) | ~825 (a) / 582 (b) |
| K22 | QB | chk 7 | `Core/Core.idr`, `Idris/Error.idr` and what only it reaches; `Frontend/Driver.idr`; the refused-program tests' `-- message:` headers | K16 | 221 (b) / ~3,000 (a) |

### Order where write paths meet

- K03 before W06 and O1 (`Exclusive.cpp`, `Exclusivity*.cpp`), W10 and O2
  (`Effects/Writer.cpp`, `Component.cpp`, `Transforms/Effects.h`,
  `Fold.cpp`, `Analysis/Effects.h`), O4 (`Inline/Inline.cpp`) and K13
  (`Identities.h`).
- `Spec/Pipeline/Pipeline.idr`: K04, then K15, W10 and K18 one at a time
  as each is ready. `Spec/Generator/Cpp.idr`: K04 before K15, W06, W10.
- K02 before K17 (`Properties.idr`), K18 (`Expect.h`), O1 and O2
  (`Contracts.cpp`). `lib/Transforms/CMakeLists.txt`: K02 before K18.
- K07 before K10 (marker lines of `Show.cpp`, `Printing.cpp`), K15
  (rt 3's `entry`), K19.
- K04 before K12 (`Families/Declarations.idr`), K13 (`Spec.idr`), K14
  (`Core/Types.idr`), K17 (`Generator/Outputs.idr`).
- K13 before O4 (`IR/Func/Call.cpp`, `Tail/*`). K12 before W07
  (`OpsClosures.cpp`). K15 before K19 (`Lower/Statics.cpp`) and W10 (the
  statics' preservation). K05 before K20.
- K08 before W05 and before K16's `Driver.idr` hunks. K14 before K21.
- Units of one fact in different lanes land together in the one cutover:
  fe 2 with ver C28's trait; ana A with C15's `CalleeFacts` (F1).

---

## 5. Totals

| Units | Lines deleted |
|---|---|
| Wait on nothing (K01 to K09) | ~10,010 (+ up to 381 symptom lines on reading) |
| Wait on a running lane (K10 to K17, two fold-ins) | ~9,260 |
| Wait on a measurement (K18 to K20, tt 11) | ~1,280 (up to; 575 of it is dep 11's two patches) |
| Counted in all | ~20,550 |
| Wait on the owner (K21, K22) | QA 825 or 582; QB 221 or ~3,000 |

Not counted: dia 1's 902 (U11's), pipe 4a (O4's), idr-constants (D132's,
done), the proposal and handoff text the coordinator strikes, and every
line the rederivation plan's units delete.

The three largest units: **K16**, the checker (~6,770: unreached
definitions, the `%runElab` runner, interface hashing, the IDE's
metadata); **K01**, tests and benchmarks (~4,760, 3,390 of it
`tests/file-size`'s padding for a rule deleted on 2026-10-03); **K05**,
upstream reports and PINS.md (~2,360, 1,596 of it Idris reports that hold
no patch). The three largest candidates: tt 1 (3,390), chk 1 (2,854),
chk 2 (1,690).
