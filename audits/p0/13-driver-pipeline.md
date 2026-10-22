<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 13: driver-pipeline

Scope: `foreign/idr/lib/Transforms/Pipeline.cpp`, `lib/Driver/`,
`lib/Target/`, `lib/Support/Profile.cpp` and `Actions.cpp`,
`tools/idris-mlir.cpp`, `idris-mlir-opt.cpp`, `idris-mlir-reduce.cpp`,
`foreign/idr/CMakeLists.txt` and every `lib/*/CMakeLists.txt`, the
top-level `CMakeLists.txt` and `CMakePresets.json`,
`foreign/idr/unittests/`, `tools/self.sh`, `tools/profile.sh`, the build
flags of `tools/bootstrap.sh`, and the Makefile's build targets.

Marks: *read* (path:line, commit, proposal section), *measured* (count, with
command), *recalled*, *conjecture*.

## 1. Reading notes

Written while reading, in order; each note names what in the proposal
bears on the pipeline, the driver, the target, the tools, the build,
profiling, threading or verification's cost.

**§0–§4.**
- §2 brief: `lib/Driver`, `lib/Target`, `lib/Support`, `unittests` =
  5,358 lines; `tools/` (4 drivers + tblgen) = 3,450. C++26 already
  (`CMakeLists.txt:317`). 22 `std::mutex`/`std::atomic`/`SmartMutex`, 10
  `parallelFor*`, 105 `getAnalysis<`/`AnalysisManager` across the tree.
  Pipeline: "one fixed sequence, no flags", listed as dedup, defunc,
  knots, effects, contify, optimize, symbol DCE, columns, canonicalize+CSE,
  structure loops, bufferize, accumulate, frames, counting (4 passes),
  demand, TRMC, tail loops, narrow, lower, entry, transform schedule,
  linalg-to-loops, LLVM lowering, tail calls.
- §3: stage-1 module 71 MB / ~70,000 functions; the pipeline has never
  finished on it. 98c6315c: `idr-optimize` threads queued on the
  context's write lock (mutable type facts read under the lock) — the
  one threading wall in the table, and it is a context fact.
- §4 "Threaded by construction": every analysis states what it reads,
  writes, what may run beside it; no global lock on a hot path; MLIR's
  pass manager does the parallelism. AGENTS.md: grades verified after
  every pass; a budget never rejects; per-target only in the target's
  entry; static linking.

**§5.1 mlir-analysis.**
- A5: the solver's `StorageUniquer` is built with threading on and never
  told otherwise; U1 adds `uniquer.disableMultithreading()`.
- A7/F3: SCCP's `getPropertiesAsAttribute` uniques a dictionary per
  distinct property set in the context: context memory that outlives
  the pass, and a context lock per op. Bears on context memory growth
  and on how a run is measured (W5).
- C2/C4/H3: per-region interface queries on matches; quadratic. A
  pipeline concern only through verification walks (does our verifier
  query per region?) — checked in §3 below.
- D2/D3: `RecursiveMemoryEffects` on a match is a whole-body walk per
  query; every canonicalize's DCE asks. The pipeline's canonicalize
  placement multiplies this (W4 is lane 02's; pipeline bears on how
  often canonicalize runs).
- E1: upstream inliner parallelizes only within one SCC; on singleton
  SCCs it is serial. 5.1.2 item 7: a wavefront over the SCC DAG is the
  solver layer's to provide.
- **F1 (central):** analyses cached per op in `NestedAnalysisMap`; a
  nested pass may read the parent's cached analyses
  (`getCachedParentAnalysis`) but not compute them; child maps created
  serially before the parallel loop. Threading contract: compute
  whole-program facts in a module-level pass/analysis, read read-only
  from nested parallel passes, invalidation drops them.
- **F2 (central):** parallelism = `OpToOpPassAdaptor`'s `parallelForEach`
  over the *immediate* children of the anchored op of a nested pipeline;
  for us module → `idr.program` → function; functions must be
  `IsolatedFromAbove`.
- **F3:** registered ops lock-free; parametric type/attr: thread-local
  cache, then shard reader lock, created under writer lock; mutable type
  mutation takes writer lock; reads of mutable part unsynchronized.
- G2: the action framework and debug counter: the upstream way to name,
  trace and bisect units of work, free with no handler. Bears directly
  on `Support/Actions.cpp` and `Profile.cpp`.
- H1: V ≈ 10 million values at the point `remove-dead-values` ran (if
  the per-value arithmetic holds); W1 asks for V, B, P, F per pipeline
  point.
- 5.1.3 Design 1: function-anchored passes reading module summaries via
  `getCachedParentAnalysis`; peak = largest function × threads. Design 3:
  each solver unit (function, SCC) an action.
- W-items in my scope: **W6** (every per-function pass anchored on the
  functions, module → `idr.program` → function); W1 (counts, which need
  a run; I give what the source says); W5 partly (attribute creation on
  hot paths: the pipeline's own passes and the verifier).

**§5.2 mlir-ods (verification at scale).**
- **H1:** verifier order per op; on exit, all `IsolatedFromAbove`
  children verified **in parallel** (`Verifier.cpp:357-371`); dominance
  a second walk per isolated op.
- **H2:** a type/attr `verify` runs once per unique instance: a fact in a
  type verifier costs nothing after creation.
- **H3 (central):** after every pass the pass manager verifies the op
  the pass ran on, recursively, unless the pass preserved all analyses
  (`Pass.cpp:621-642`). A module (or `idr.program`) pass re-verifies all
  70,000 functions even if it touched three; a function pass verifies
  only its function on its own thread.
- H4: `RegionBranchOpInterface` brings a region verifier run on every
  verify; the verifier's cost is counted inside each pass's time; measure
  as the difference with `--verify-each=0`.
- H5: symbol checks in `verify()` with `lookupNearestSymbolFrom` are a
  linear scan per op; in `verifySymbolUses` they are one shared
  `SymbolTableCollection`.
- E2: greedy driver's non-convergence returns `failure()`, which a caller
  must not turn into a rejection (AGENTS.md budget rule). Pipeline: who
  calls `applyPatternsGreedily` and whether failure is fatal.
- E3: walk driver terminates by construction (AGENTS.md's shape).
- D2/M10: mutable types: writer lock on `mutate`, reads unlocked; 98c6315c
  came from a uniquing or mutating call on a read path (W6 is lane 01's).
- **M11:** levers for verifying after every pass at 70,000 functions:
  nest passes on functions; `markAllAnalysesPreserved()` when a pass
  changed nothing (verifier skipped); symbol checks in
  `verifySymbolUses`; grades in type verifiers.
- 5.2.3 row 19: pass facts in `Passes.td` (`Pass<>`, options,
  statistics, dependent dialects) generate `impl::XBase`, registration,
  docs. §2 counts only **4 pass definitions** in TableGen; the pipeline
  runs about 30 passes: the gap is mine to inventory.
- Design 3: per-pass verification local, parallel per function, linear;
  costs "the pipeline nested on functions where a pass allows it (§5.1
  and wave 2 judge which)" — that judgement is this lane's.
- Owner question **Q6 (ods-Q6)**: accept that a module pass re-verifies
  all functions, or make nesting on functions a rule of the pipeline?
- W-items in my scope: **W7** (measure the verifier: with/without
  verify-each; count module passes), **W9** (do passes that change
  nothing mark all analyses preserved?), W3's last clause (any whole-
  module walk of ours run per pass), W8 (does any stage write or read
  bytecode — the driver's I/O).
- 5.2.5 note to oom: `MLIRContext::beginTransientScope` frees types and
  attributes created inside the scope: a per-pass bound on context
  growth, with D2's restriction (no mutation of a base instance inside).

**§5.3 llvm (threading, the C++ baseline).**
- A2/E5: no RTTI, no exceptions in LLVM (`-fno-rtti`/`-fno-exceptions`);
  M11: holds for us too since we link LLVM's static libs; `std::any`,
  `dynamic_cast`, `typeid` out. Build flags: check what our CMake sets.
- **D1 (central):** two pools. `llvm/Support/Parallel.h`
  (`parallelFor`, `parallelForEach`, `TaskGroup`) runs on a *global*
  executor; MLIR's `mlir/IR/Threading.h` runs on the `MLIRContext`'s
  pool, orders diagnostics, runs serially when multithreading is off,
  and helps in nested calls. `llvm::parallelFor` inside an MLIR pass puts
  a second pool beside the context's (*conjecture*: oversubscription).
  The pass manager's op-to-op adaptor claims a cloned pass manager per
  worker by CAS (`Pass.cpp:985-1010`).
- D2/D3: lld/BOLT partition by owner or freeze; BOLT's cost-weighted
  static partition (`runOnEachFunction`) by instruction count.
- M8: whole-program solves over the call graph's condensation level by
  level with `mlir::parallelForEach` on the context's pool; each of §2's
  22 mutex/atomic and 10 `parallelFor*` checked against that model.
- M9: budgets: Attributor's (pessimistic state) fits AGENTS.md; clang's
  (an `Expected` error) must never be copied.
- M10: LLVM moving `cl::opt` globals into TableGen-declared option
  structs (`LibraryOptions.td`, `PassesOptions.td`). Bears on our driver's
  options.
- E5: "No static constructors" (`CodingStandards.md:600-640`) constrains
  global registries (pass registration, `cl::opt` globals in our tools).
- S1's threading: per-function solves under the pass manager; whole-
  program solves SCC level by level on `mlir::parallelForEach`; actions
  per unit; `Solution` cached in `AnalysisManager`.
- Owner questions in my set: **Q-llvm-6** (determinism as a tested
  invariant: run each analysis with one thread and with many, compare
  frozen solutions). Also Q-llvm-1 (compile time measured as part of P0:
  the build's job), Q-llvm-3 (numbering as a cached analysis).
- Wave-2 question in scope: every `std::mutex`/`std::atomic`/`SmartMutex`
  and `parallelFor*`: which pool, what is it protecting (I own those in
  my files; the rest are other lanes').

**§5.4 modular (verification in release builds, threading, build).**
- **F10:** one thread pool for everything (the context's pool is
  AsyncRT's CPU device behind `ThreadPoolInterface`); shared state named
  by type (`Shared<T>`, `ThreadLocalCache`, `ConcurrentAppendingVector`).
- **F15:** three tiers of state in the borrow checker: whole-program
  immutable maps populated before threading; a per-thread cache reset
  between functions; per-function state. Driver is one
  `failableParallelForEach(ctx, range, func, cache, consolidate)`.
- **F16 (central):** Modular calls `enableVerifier(false)` under
  `MODULAR_PRODUCTION` (`Support/lib/Config.cpp:24-28`); nested pass
  managers inside passes disable it unconditionally; an explicit
  `kgen-verifier` pass runs at chosen phase boundaries, verifies op by op
  without recursion, stops at an error limit; parameters verified by a
  pass between phases.
- F13/design 8: Modular's build flags: C++20, `-fno-rtti -fno-exceptions
  -Wall -Wextra -pedantic -Wthread-safety -Wcovered-switch-default
  -Wsuggest-override -Werror=global-constructors`, `-Werror` in CI,
  clang-tidy as a test. Design 8: `-Wthread-safety` with real annotations
  (libc++'s `std::mutex` is a capability; LLVM's `RWMutex` on Apple is
  unannotated). Bears directly on our CMake flags.
- F17: options selecting between two implementations are forbidden here
  (hard cutover); wave 2 checks every option or flag that selects
  between two implementations — the driver's flags are mine.
- F18: driver-tblgen: option records parsed once into typed views,
  validated, generators registered by name. Model for our driver's
  options (with §5.3 M10's `LibraryOptions.td`).
- F19: tracing compiled out by a `constexpr` level in the type
  (`TimeTraceScope<Trace::kCompiler, ...::isEnabled()>`). Bears on our
  Tracy zones and action profiler.
- 5.4.4 oom note: Mojo installs a bad-alloc handler that prints an
  actionable message and exits 1 (`OOMHandler.h:24-37`).
- Design 2: per-worker parallel driver; deletes ad hoc mutexes around
  shared caches. Design 8: mechanical enforcement in the build.
- Owner question in my set: **Q-M2** (verification at 71 MB: grade check
  after every pass always; full structural verifier after every pass in
  development and at phase boundaries in release?).
- Wave-2 questions in scope: "whether release builds verify after every
  pass today, and what it costs" (Q-M2); "every option or flag that
  selects between two implementations" (F17) — for the driver and the
  pipeline.

**§5.5 cxx26 (build flags, PCH, hardening).**
- A.5/D8: libc++'s own hardening modes (none, fast, extensive, debug; no
  ABI change; set per TU before any header, or as the vendor default
  `LIBCXX_HARDENING_MODE`); the standard's P3471 is not in libc++.
- A.6: LLVM's build is `-fno-rtti -fno-exceptions -funwind-tables`; the
  library's throwing paths become aborts.
- **D.11:** one TU of MLIR's core headers costs 1.5 s; a PCH makes it
  0.43 s (host). Upstream: `add_mlir_library(... PRECOMPILE_HEADERS)`,
  `MLIRIR` precompiles `mlir/IR/pch.h`, a dependent target reuses its
  dependencies' PCH (`AddLLVM.cmake:82-147, 586-614`). PCH off under
  `LLVM_ENABLE_MODULES`, with GCC, and with clang < 18.
- D.15: LLVM chose PCH over modules (Engelke RFC: front end ~3x, wall
  139 s → 86 s on 48 cores).
- E.14: modules not ready for MLIR; `import std` experimental.
- 5.5.2: if ~250 TUs include MLIR's core, headers ≈ 6 CPU-minutes per
  clean build, ≈ 2 with a PCH (*conjecture*).
- **D6 (central):** one PCH for `foreign/idr` (MLIR's `pch.h` set, ADT,
  dialect headers) via `PRECOMPILE_HEADERS` or
  `target_precompile_headers`; `-Xclang -fno-pch-timestamp` with ccache;
  an installed LLVM's PCH cannot be reused out of tree (*recalled*), so
  the PCH is ours; a PCH fixes macros every TU sees, so libc++'s
  hardening mode becomes per target. `-ftime-trace` run as baseline;
  `extern template`; unity builds and modules rejected for P0.
- D8: `LogicalResult`/`FailureOr` where the diagnostic went to the
  context; `std::expected<T, Reason>` where failure is data;
  **`llvm::Error`/`llvm::Expected` in the driver**; libc++ extensive mode
  in debug and test builds of our tools, measured for release, set as
  the bootstrap's `LIBCXX_HARDENING_MODE`.
- Owner questions in my set: **cxx-Q3** (PCH now, modules not in P0),
  **cxx-Q4** (libc++ hardening mode for debug/test; release measured or
  unchecked).
- Wave-2 question in scope: "The build: how many TUs include MLIR's
  headers, whether the pinned clang that compiles `foreign/idr` is built
  with assertions, and whether PCH or ccache is in use. A `-ftime-trace`
  run of today's build is the baseline for D6."

**§5.6 ecosystem.**
- E1: Flang nests every pass on the top-level ops
  (`addNestedPassToAllTopLevelOperations`), so the pass manager supplies
  the parallelism; no `parallelFor` anywhere in `flang/lib`.
- D2: IREE's `FixedPointIteratorPass` (rerun a nested pipeline until no
  pass sets a discardable attribute, up to 10, then fail) is what
  AGENTS.md rules out twice. The pipeline must have no such loop.
- D3: IREE scopes upstream's solver to one function by `FunctionLikeNest`.
- D4: IREE rebuilds whole-program DFX analyses in every pass (14 files):
  the rederivation chain at whole-program scale; cache in
  `AnalysisManager` and preserve by name (H3: CIRCT
  `markAnalysesPreserved<InstanceGraph, InstanceInfo>()` in 15 files).
- H5: parallelism per function or module, never inside a solve.
- Design 1: `ProgramGraph` an `AnalysisManager` analysis on
  `idr.program`, kept up to date by passes that change calls, preserved
  by name. The pipeline's job: pass order + preservation declarations.
- W-E3 (analyses computed by more than one pass) and W-E5 (every budget,
  round count and iteration cap "in our solvers and pipeline, and whether
  any becomes a failure") touch my files; W-E4 (facts in discardable
  attributes, including "changed" flags) touches the pipeline/driver.

**§5.7 library.**
- B3: MLIR's parallelism rests on isolated-from-above ops; that is why
  MLIR has no whole-module use-def chains. Pipeline nesting rides on it.
- F4: build systems: MLIR's `AnalysisManager` is a dirty-bit rebuilder
  with a topological scheduler and no early cutoff (*conjecture*). Bears
  on preservation declarations.
- F5: typescript-go: pool of checkers, each with its own caches, work
  partitioned for locality; nothing mutable shared under a lock.
- G3: Zig's InternPool thread ids in an index's top bits make indices
  schedule-dependent: thread-tagged ids must never order output (M8).
- L2 "upstream first": `int-range-optimizations` nested per function
  measured 3 s against 30 s module-wide
  (`notes/compile-pipeline/upstream-mlir-llvm.md` §4). Direct evidence
  for nesting in the pipeline.
- Owner question in my set: **QL4** (byte-identical output for any
  thread count a requirement?).
- Wave-2 question: stage-1 counts (ops, values, regions, blocks,
  functions, largest function, SCC sizes, largest match); I give how
  a run would measure them (the driver's statistics), not the counts.

**§5.8 dialect-design.**
- **B9 (central for nesting):** a pass "must not inspect the state of
  operations that are siblings of the current operation ... inspecting
  ancestor/parent operations is permitted" (`PassManagement.md:29-31`).
  A type whose body lives in a sibling declaration op cannot be read by a
  function pass in parallel; a body on an ancestor (`idr.program`'s
  attribute) can. A direct call's callee is a sibling: a function pass
  may not read its type (T6, DS2.1). Decides which of our passes can nest
  on functions.
- B8: mutable types the exception; transient scopes reclaim storage.
- **B10:** verifiers are local; whole-function invariants are passes
  ("run after every pass by instrumentation if AGENTS.md's 'verified
  after every pass' needs it", EF3). Bears on how the grade check runs:
  op verifiers (pass-manager verify) vs a `PassInstrumentation`.
- O4: an op legal only before or after a pass is a `ConversionTarget`
  matter, not attributes (closures legal only before defunc).
- DS3.1: an immutable table on the ancestor `program` op, readable from
  any nested pass (B9).
- Wave-2 question in scope: "How the grade verifier runs (op verifiers
  or a pass), whether it follows def-use chains (B10), and its cost on
  the stage-1 module" — the pipeline's verification is mine; the
  verifier's content is lane 01's.

**§5.9 mlton (the pass driver).**
- **A1-A2 (central):** MLton's optimizer is a plain list of `{name, doit,
  execute}` records folded over the program; the order is data, with the
  reason for each constraint in a comment beside the entry
  (`ssa/simplify.fun:59-62, 105-113`); the list can be replaced from the
  command line by name (`:256-278`). The model for `Pipeline.cpp`.
- **A3 (central):** the IR's type checker runs at every IR boundary but
  not after each pass inside an IR by default; Machine's checker off as
  "too slow"; after every pass the driver can print property-list and
  hash-set statistics and the live heap: footprint per pass a first-class
  report.
- A4: what a pass needs from its input is established by the pass or
  written as a contract (precondition, postcondition).
- E3: the shrinker is the normal form between passes, called by each
  pass over what it rewrote; no module-wide cleanup pass. Pipeline:
  where our canonicalize/CSE runs are only cleanup.
- G2.10: measurement as part of the driver.
- M11: verification at IR boundaries only; AGENTS.md is stronger;
  "our verifier should be that cheap at 70,000 functions".
- M12: per-function passes are what MLIR parallelizes over `func` ops.
- **Design 6:** footprint of every pass as a first-class report: a Tracy
  plot per pass of the solver layer's arena bytes, cell counts and the
  process footprint. Directly my subsystem (profiling, how a run is
  measured).
- Owner question in my set: **Q-O5** (keep grades verified after every
  pass as the contract; treat its cost at 70,000 functions as a measured
  budget of the verifier?). Wave-2 **Q-W7** (grade verifier cost per
  pass; is it one linear walk) bears on the pipeline's verification.

**§5.10 rc.**
- M1: every counting algorithm in the field is per function, reading
  other functions only through signatures; Lean runs its whole impure
  pipeline one SCC at a time (`Main.lean:200-215`).
- **R1.3:** per-function counting passes "nested under the pass manager
  on `idr.func` so MLIR runs them in parallel". The nesting is the
  pipeline's; the passes are lane 08's.
- M3/W5: if the grade verifier is OSSA's rule, it is a linear walk per
  function. Its scheduling (after every pass) is mine.
- M10/W8: pass order: Koka runs TRMC before Perceus; ours runs counting
  before TRMC. Order is in `Pipeline.cpp`; the judgement is lanes 08/10's.

**§5.11 oom (central: the compiler's own memory, subject A).**
- O1: walls were memory after the time walls fell; jetsam killed a
  traced run at 43 GB RSS "(low-swap, on 96 GB)" in idr-frames; each
  fixed at the representation.
- O2: the compiler's tools share the runner's 64 GiB stack reservation
  (`idris_rt_run_on_stack`).
- O3: memory is "a record, not a gate" (0001 D4); bounded memory
  measured by `peak_memory` (0006 §1), test not yet written.
- K5: jetsam kills on `phys_footprint` (compressed pages included); RSS
  under-reads it. `task_info(TASK_VM_INFO)` reports `phys_footprint`,
  `ledger_phys_footprint_peak`, `limit_bytes_remaining`; pressure signal
  is libdispatch's `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE` in libSystem.
- K2/K4: Linux OOM score = resident + swap + page tables; PSI triggers
  pollable.
- **C1:** LLVM's OOM policy is `report_bad_alloc_error`: "LLVM ERROR: out
  of memory" and `abort()`; `InitLLVM` installs a new-handler.
  `-time-passes -track-memory` reads `mallinfo2`/
  `malloc_zone_statistics`: blind if snmalloc replaces malloc in our
  tools (*conjecture*).
- **C2:** MLIR has no memory accounting; the pass manager clears a nested
  pipeline's analyses when it finishes (`Pass.cpp:673-679`); uniqued
  types/attrs live for the context except in a `TransientScope`
  (single-threaded, no IR referencing them). `PassInstrumentation` is
  where a per-pass memory record goes.
- C3: rustc prints per pass the RSS before/after (`profiling.rs`).
- **C7:** determinism is the binding constraint on a compiler's budget:
  a budget in program units (ops, rewrites) gives the same output on
  every machine and thread count; one in bytes or seconds does not, and
  breaks stage 2 = stage 3 (0001 D8) and the determinism tests (0006 G1).
- 5.11.2 (A): "degrade when memory is short" is not available; passes
  acceptance rests on cannot be budgeted at all; running out is a crash
  of the machine; today the OS kills with SIGKILL and nothing is
  written; measure what the OS kills on.
- **A2 (central):** one `PassInstrumentation` (`runAfterPass`) reads the
  footprint through one platform function (macOS `phys_footprint` and
  peak; Linux cgroup `memory.current`/`memory.peak`, else resident +
  swap) and writes it into `-mlir-timing`'s report and the action
  profile.
- **A3:** name the death: on the platform's pressure signal flush the
  action profile and write one line (pass, function/node, footprint);
  refuses and stops nothing; a watcher thread behind the platform layer.
- **A4:** budgets in program units only.
- Owner questions in my set: **oom-2** (the compiler running out: a
  crash, not a refusal; budgets in program units), **oom-3** (footprint
  record per pass; which measure).
- Wave-2 questions in scope: **3** (is snmalloc the compiler's own
  malloc; `peak_memory` in `tools/host.sh` reads what?), **8**
  (attributes passes create per function; any phase under a
  `TransientScope`), **9** (is the action profile written
  incrementally, so a killed run keeps its tail?).

**§8 owner questions in my set** (to give evidence for, §6 below):
ods-Q6, Q-M2, Q-O5 (§8.6 verification, "answer together"); QL4,
Q-llvm-6 (§8.7 threading and determinism); cxx-Q3, cxx-Q4 (§8.9);
oom-2, oom-3 (§8.11); Q2 (self-hosting: does 0001's S3 rerun stop until
P0's plan is approved), Q4 (who runs the release `idris-mlir` on the
stage-1 module for P0's measurements) (§8.2).

**§9 decisions:** D1 P0 first; D2 own solvers allowed, honestly named,
composition and threading clear; D3 wave-1 rule; D4 no code until the
whole plan is approved.

**Proposal 0003 (facts once), the items that fall in this lane.**
- §1 rule: keep a fact when re-deriving is a guess or more than linear;
  derive it when it is a total cheap function of a smaller one source.
- *Target lane, "One target machine recipe":* MLIR-side builds use
  `getTargetMachine(TargetAttr)` with default options, codegen uses
  `idr::target::machine`: vector width, required CPU bits and the
  return-register answer come from differently configured machines.
  idr-target writes every target fact once into the DLTI spec; `Run.cpp`
  stops resetting triple and layout from constants; `OsOp::fold`'s
  fallback to the build machine's triple goes. A first attempt
  (2026-10-19, reverted) refused every module because LLVM's structural
  `DataLayout::operator==` compared unequal.
- *Function facts not lowered* (`effects`, `total` → `willreturn`,
  `mustprogress`, `nounwind`, `memory`): lane 12's (LowerFunc).
- *No line tables:* run `ensure-debug-info-scope-on-llvm-func` before
  translation: a pipeline/driver item.
- *Driver errors sit at `UnknownLoc`* though the path is known.
- *No stack probes against the 1 MiB guard:* set
  `"probe-stack"="inline-asm"` (with §5.11 B2: a target-entry fact).
- *`make compile OUT=` keeps only the basename.*
- *Held twice or re-parsed:* `uname` for target names (read a CMake
  fact); the handoff dialect list twice; compile_commands re-read;
  `page-size-mismatch` hand-spells flags `baseline-cpu-flags` holds.
- *Defunc lane, "Analyses dropped and rebuilt":* `Effects.cpp` preserves
  only `SymbolTable`; `TypeGraph(op)` built directly by the program
  verifier after every pass; `Layouts` should take the AnalysisManager.
  The program verifier after every pass is the pipeline's
  instrumentation: mine to measure.
- *"Exclusivity is no analysis":* the final solve handed to
  `createRcCommit` by constructor (`Ownership/Exclusive.cpp`), so nothing
  reads it cached and it has no timing row. Owed: a cached program
  analysis and idr-rc-commit a pass of its own reading it with
  `getCachedParentAnalysis`. A pipeline-shape item (lane 08 owns the
  solve).

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*: `wc -l`, at e96bb991 plus the working tree)

| part | files | lines |
| --- | --- | ---: |
| the pipeline | `lib/Transforms/Pipeline.cpp`, `include/idr/Transforms/Pipeline.h` | 214 + 119 |
| the driver | `lib/Driver/*.cpp` (10), `include/idr/Driver/*.h` (8) | 2,216 + headers |
| the target | `lib/Target/*.cpp` (5), `Target.h`, `ScheduleOps.td` | 957 + 181 + 38 |
| profiling | `lib/Support/Profile.cpp`, `Actions.cpp`, `Profile.h`, `Actions.h` | 238 + 32 + 83 + 67 |
| tools | `idris-mlir.cpp`, `idris-mlir-opt.cpp`, `idris-mlir-reduce.cpp` | 10 + 95 + 90 |
| build | top `CMakeLists.txt`, `CMakePresets.json`, `foreign/idr/CMakeLists.txt`, `lib/CMakeLists.txt`, `lib/{Support,IR,Analysis,Target,Transforms}/CMakeLists.txt`, `unittests/CMakeLists.txt` | 389 + 56 + 260 + 187 + 18 + 118 + 46 + 46 + 556 + 79 |
| unit tests | `unittests/*.cpp` (12) | 1,862 |
| scripts | `tools/self.sh`, `tools/profile.sh`; `tools/bootstrap.sh`'s flags; `Makefile` build targets | 141 + 104; (1,603); (398) |

Command: `wc -l foreign/idr/lib/Transforms/Pipeline.cpp foreign/idr/lib/Driver/* foreign/idr/lib/Target/* ...` (§9 lists every file).

### 2.2 The pipeline as it runs (*read*: `Pipeline.cpp:61-197`, `Run.cpp:153-154`, `Passes.td`)

One `mlir::PassManager` on the `builtin.module` (`Run.cpp:140`), verification on (upstream's default, `.toolchain/llvm-project/mlir/lib/Pass/Pass.cpp:1020-1028`; the driver never calls `enableVerifier`, and `registerPassManagerCLOptions` has no option for it, `lib/Pass/PassManagerOptions.cpp:23-80`). Anchors and stages from each record of `Passes.td` (the `IdrPass<arg, anchor, role, requires, sets>` fields):

| # | step | anchor | role | stage | parallel how | after it the verifier |
| ---: | --- | --- | --- | --- | --- | --- |
| 0 | idr-target | module | lowering | any | — | skipped (`markAllAnalysesPreserved`, `Target.cpp:93`) |
| 1 | idr-deduplicate | program | optimization | any | `parallelFor` inside (`EliminateDuplicateFunctions.cpp:101,152`) | whole program, unless nothing merged |
| 2 | idr-defunctionalize | program | lowering | higher→first | `failableParallelForEach` (`Defunctionalize/Pass.cpp:138`) | whole program |
| 3 | idr-knots | program | check | first | — | skipped (preserves all) |
| 4 | idr-effects | program | analysis | first | `parallelFor` in the analysis (`Analysis/Effects.cpp:63`) | whole program (preserves `SymbolTable` only, `Effects/Effects.cpp:39`) |
| 5 | idr-contify | program | optimization | any | — | whole program unless nothing moved |
| 6 | idr-optimize | program | optimization | first | waves (`Waves.cpp:337`) + a dynamic pipeline per node (`Component.cpp:85-97`) | whole program; and its function after every inner pass of every node |
| 7 | symbol-dce | program | (upstream) | — | — | whole program, always (upstream never preserves) |
| 8 | idr-columns | program | optimization | first | — | whole program |
| 9 | [canonicalize, cse] | func | (upstream) | — | pass manager, per function | each function; then the program's own verifiers |
| 10 | symbol-dce | program | | | | whole program, always |
| 11 | [idr-structure-loops] | func | lowering | first | pass manager | each function; then the program's own |
| 12 | idr-bufferize | program | lowering | first | — | whole program |
| 13 | [canonicalize, cse] | func | | | pass manager | each function; then the program's own |
| 14 | idr-accumulate | program | optimization | first | — | whole program unless no clone |
| 15 | idr-frames | program | optimization | first | — | whole program unless no frame |
| 16 | [idr-rc-cells] | func | lowering | first | pass manager | each function; then the program's own |
| 17 | idr-rc-stack | program | optimization | first | (Reuses' `parallelForEach`, `Reuses.cpp:276`) | whole program unless no cell moved |
| 18 | idr-rc-grades | program | lowering | first→graded | two `parallelForEach` (`Grades.cpp:41,54`) | whole program |
| 19 | idr-rc-exclusive | program | lowering | graded→owned | `runPipeline` of a hand `RcCommit` per function (`Exclusive.cpp:50-53`) | the program's own (inner group), then whole program |
| 20 | symbol-dce | program | | | | whole program, always |
| 21 | idr-demand | program | check | owned | — | skipped |
| 22 | idr-trmc | program | optimization | owned | — | whole program unless no clone |
| 23 | [idr-tail-loops] | func | optimization | any | pass manager | each function; then the program's own |
| 24 | idr-narrow | program | optimization | owned | `runPipeline` of idr-narrow-words (`Narrow.cpp:168-171`) | the program's own (inner group), then whole program |
| 25 | idr-lower | module | lowering | owned→lowered | `failableParallelForEach` (`Lower.cpp:220`) | whole module |
| 26 | idr-entry | module | lowering | lowered | — | whole module |
| 27 | [transform-interpreter, idr-narrow-lanes, convert-linalg-to-loops, canonicalize, cse] | func.func | | | pass manager | each function |
| 28 | idr-returned-arguments | module | optimization | any | `runPipeline` of the drop per func.func (`ReturnedArguments.cpp:139-141`) | whole module |
| 29 | [canonicalize, cse, convert-vector-to-scf, expand-strided-metadata, lower-affine, scf-to-cf] | func.func | | | pass manager | each function |
| 30-32 | convert-vector-to-llvm, convert-to-llvm, reconcile-unrealized-casts | module | | | | whole module each |
| 33 | idr-tail-calls | module | lowering | any | `parallelForEach` (`TailCalls.cpp:148`) | whole module |

*Measured by reading:* on `idr.program` there are 19 program passes, 5 nested function groups holding 7 function passes, and 2 nested `runPipeline`s inside program passes; on the module, 10 module passes and 2 `func.func` groups holding 11 passes. Of the 29 `IdrPass` records (`grep -c 'IdrPass<"' Passes.td`), 25 are added by `Pipeline.cpp` and `Run.cpp` (*measured*: a `grep` of each generated constructor, §2.7), 2 are inner steps (idr-narrow-words, idr-returned-arguments-drop), 1 a report (idr-binding-times), 1 a test check (idr-expect); `RcCommit` is a `PassWrapper` declared in no `.td` (`Commit.cpp:153-183`).

### 2.3 What verification costs per pass, by reading the pinned verifier

- After a pass, the pass manager verifies the op it ran on, recursively, unless the pass preserved all analyses; after an adaptor (a nested group, or a `runPipeline`) it verifies non-recursively (`Pass.cpp:621-642`).
- A non-recursive verify still runs the op's own `verifyInvariants` on entry (`Verifier.cpp:313-315`) and its `verifyRegionInvariants` on exit (`:376-380`): only the walk into children is skipped (`:357-365`, `:454-456`).
- `idr.program`'s own verifiers are three single-threaded walks of the whole program: `ProgramOp::verify` walks every op's attribute dictionary, result types and block argument types for undeclared data types (`lib/IR/Func/Func.cpp:56-89`); the `SymbolTable` trait's region verifier checks names and every call's `verifySymbolUses` (`Call.cpp:29`); `ProgramOp::verifyRegions` then runs `verify::program` (`Func.cpp:105-118`), which checks the target, walks every call of every function for effects (`Verify/Program.cpp:61-79`), builds a `TypeGraph` of the program (`:266`), and in the owned stage walks every recycle and builds `Layouts` (`:99-120`).
- Each function's `verify::function` (stage rules, flow, linearity, lifetimes, owned rules, `Program.cpp:300-308`) runs in parallel over the functions (`Verifier.cpp:357-371`) on a recursive verify, and alone on a function pass's verify.
- So, *by reading* (an upper bound, the counts of §2.2): 19 program passes and 7 adaptors give up to 26 runs of the program's three single-threaded whole-program walks (about 78 walks) and up to 19 parallel re-verifications of every function, per compilation; idr-optimize adds a function verify after each of its five inner passes for every node it runs (`Component.cpp:85-97`; the inner pipeline's steps are listed in `Passes.td:246-251`). The verifier's time is inside each pass's `-mlir-timing` row and its time-trace zone (both close in `runAfterPass`, after the verifier, `Pass.cpp:619-650`), and outside its `PassExecutionAction` span, which wraps `runOnOperation` alone (`Pass.cpp:604-614`): the difference between the two is the verifier, measurable on today's binaries (§8).

### 2.4 Facts the subsystem holds, derives and hands on

- **The pipeline's order and nesting**: C++ statements (`Pipeline.cpp:61-197`), with a reason beside most steps. Held again, in another order, as the order of `Passes.td`'s records, which `Passes.td:47-48` says is "the pipeline's order" and from which `IdrPassStages.txt` is generated: it puts idr-effects before idr-knots (`Passes.td:169,190`; pipeline `:74,77`) and idr-frames before idr-accumulate (`Passes.td:430,456`; pipeline `:122,125`) (*measured*, by reading both). The harness reconstructs the pipeline by parsing `--dump-pass-pipeline` text with `awk` (`harness/lib/differential.sh:15-60`).
- **The stage chain**: each pass's `requires`/`sets` (`Passes.td:41-71`), checked at run time by `StagedPass` (`Pipeline.h:30-77`), never statically (0004 §8, "The stage chain, unchecked").
- **The target**: the triple and both CPUs, generated into `idr/TargetEntry.h` from the target's entry (`foreign/idr/CMakeLists.txt:62-76`); written on the module by idr-target as `#llvm.target`, `dlti.dl_spec` and `dlti.target_system_spec` (`Target.cpp:61-94`), which computes the vector width with a second machine (`LLVM::detail::getTargetMachine`, `Target.cpp:66-67`) while code generation uses `idr::target::machine` (`Optimize.cpp:37-46`); `Run.cpp:194-195` then resets the LLVM module's triple and data layout from constants.
- **The runtime's identity**: archive digest, CPU, features (`Runtime.h:69-77`; build list `RuntimeDigest.cmake`), checked at link (`LinkRuntime.cpp:42-65`).
- **The verdict and the report**: `Outcome` (`Verdict.h:69-110`), folded from every diagnostic (`Outcome.cpp:164-171`) and every pass statistic (`Outcome.cpp:125-160`).
- **The trace**: LLVM's time trace, zones per pass and analysis (`Profile.cpp:105-175`), per LLVM pass (`:178-197`), per driver phase (`IDR_ZONE_IN`, 15 sites); MLIR's action handler (`--log-actions-to`, `--profile-actions-to`, `Run.cpp:290-299`) with 26 tagged actions of ours (*measured*: `grep -rn 'static constexpr.*tag = ' lib include | wc -l`); `-mlir-timing` (`Compile.cpp:155-157`, `Run.cpp:149`).

### 2.5 Threading (*read*)

- One `llvm::StdThreadPool`, sized by `--num-threads` (default every CPU), declared before the context and given to it (`Compile.cpp:166-179`); the pass manager's groups, every `mlir::parallelFor` of the passes (13 sites in 11 files, *measured*: `grep -rn 'parallelFor\|failableParallelForEach\|parallelForEach' lib`), and the bins' code generation (`ThreadPoolTaskGroup` on the same pool, `Artifacts.cpp:290-296`) run on it. No `llvm::parallelFor` anywhere (*measured*, same grep), so §5.3 D1's two-pool hazard does not occur.
- The compilation's main thread runs on the runtime's reserved stack, 2^36 bytes behind a guard (`Stack.h:64-74`, `runtime/Start/Runner.cpp:44,61-92`; `PINS.md:595` says 2^40, stale). The pool's workers run on LLVM's default thread stack: 8 MiB on Darwin, the pthread default elsewhere (`llvm/lib/Support/Threading.cpp:81-93`).
- Locks in this subsystem: `Outcome`'s one mutex (`Verdict.h:105-109`), `StatisticsInstrumentation`'s mutex and `DenseMap<Pass *, SmallVector>` (`Outcome.cpp:157-159`), `Zones`' mutex and `DenseMap<thread id, Pipelines>` (`Profile.cpp:173-174`), the contracts' mutex (`Contracts.h:44-47`, test-only). Thirty-five lock or atomic sites in the tree (*measured*: `grep -rn 'std::mutex\|std::atomic\|SmartMutex\|RWMutex\|std::lock_guard\|std::shared_mutex' lib include tools | wc -l`), ten files.

### 2.6 Memory and measurement (*read*)

- Nothing records the compiler's footprint per pass: no `task_info`, `phys_footprint`, `mallinfo`, `getrusage` or memory-pressure source in `foreign/`, `runtime/`, `tools/` or `harness/` but `tools/host.sh:114-150` (*measured*: `grep -rn 'task_info\|phys_footprint\|getrusage\|mallinfo\|statm\|malloc_zone\|DISPATCH_SOURCE_TYPE_MEMORYPRESSURE'`).
- A run's peak is `ru_maxrss` from `wait4` (`tools/host.sh:127-150`), resident size, used by `tools/self.sh:81-84`.
- No `MLIRContext::TransientScope` (*measured*: `grep -rn TransientScope foreign`); no allocation-failure handler of ours (InitLLVM's, `Main.cpp:59`); the runtime does not override `malloc` or `operator new` (*measured*: `grep -rn 'void \*malloc(\|operator new\|snmalloc/override' runtime`), so the tools use the system's allocator and LLVM's `-track-memory` would read it (§5.11 C1's worry does not apply).
- The time trace is held in memory and written at exit (`Profile.cpp:208-215`); `-mlir-timing` prints at exit; MLIR's action profiler writes and flushes each event under a mutex as it goes (`.toolchain/llvm-project/mlir/lib/Debug/Observers/ActionProfiler.cpp:22-60`).

### 2.7 The build (*read*, *measured* where marked)

- C++26, no exceptions, no RTTI, libc++'s extensive hardening on every C++ unit in every configuration, the runtime's included (`CMakeLists.txt:317-326`); warnings as errors (`:344-361`); Release is full LTO (`:369-375`); per-target tool hardening from the entry (`:187-279`).
- ccache on every compile; no precompiled header anywhere, on the stated ground that ccache cannot cache one (`CMakeLists.txt:31-47`; `tools/bootstrap.sh:265-273`, which also turns LLVM's own PCH off).
- The LLVM/MLIR/clang our tools link and are compiled by is stage 2, `CMAKE_BUILD_TYPE=Release` with `LLVM_ENABLE_ASSERTIONS=ON` and `LLVM_FORCE_ENABLE_STATS=ON` (`tools/bootstrap.sh:1022-1031`); the typecheck build mirrors it (`:1127-1132`).
- 294 C++ units under `lib`, `tools`, `unittests`; 228 include `mlir/` directly, and 260 files include `idr/IR/IdrDialect.h`, which includes MLIR's core and the 38,361-line generated `IdrOps.h.inc` (*measured*: `find lib tools unittests -name '*.cpp' | wc -l`; `xargs grep -l '#include "mlir/'`; `grep -rl IdrDialect.h`; `wc -l build/typecheck/.../IdrOps.h.inc`).
- The only compile-time record is the stale typecheck build's `.ninja_log` (host clang, Debug, parallel, 2026-10-12 to 10-18): 353 objects, mean 7.26 s wall each; `Driver/Run.cpp` 40.1 s and `Pipeline.cpp` 19.9 s the largest of this subsystem (*measured*: last entry per object of `build/typecheck/.ninja_log`; wall time under contention, some entries ccache hits, so an indication only).

## 3. Reconciliation with the proposal

### 3.1 Findings and designs, one by one

- **§2, "4 pass definitions" in TableGen: refuted.** `Passes.td` holds 29 `IdrPass` records (*measured*: `grep -c 'IdrPass<"' foreign/idr/include/idr/Transforms/Passes.td`), each with role, anchor, stages, statistics and dependent dialects; the "4" undercounts by 25. The brief's derived claim (row 19 of §5.2.3, pass facts not yet in `Passes.td`) therefore holds only for `RcCommit` (`Commit.cpp:153-183`) and idr-optimize's inner steps (`Passes.td:273-275`: "none is registered").
- **§2, the pipeline "one fixed sequence, no flags": holds.** No option selects a pass (`Passes.td:4-5`; `Main.cpp:66-68`). The brief's order is loose: idr-target runs first (`Run.cpp:153`); knots runs before effects (`Pipeline.cpp:74,77`); accumulate before frames (`:122,125`); there are three symbol-dce runs (`:49,84,106`), two canonicalize+CSE groups before counting (`:91-95,114-118`), and idr-narrow-lanes and idr-returned-arguments after lowering (`:152,173`).
- **§5.1 F1 (compute in a module pass, read cached from nested passes): holds in part.** Nested passes exist (5 groups on functions, `Pipeline.cpp:92,110,115,38,132`), but most per-function work is done inside program passes by hand-written `parallelFor` loops (13 sites, §2.5) or by `runPipeline` with a hand pass constructed with the parent's state (`Exclusive.cpp:50-53`, `RcCommit(solved, symbols, numExclusive)`), not by `getCachedParentAnalysis`. 0003's "Exclusivity is no analysis" is still open at this line.
- **§5.1 F2 (parallelism over the immediate children; functions must be `IsolatedFromAbove`): holds.** `idr.program` and `idr.func` are both `IsolatedFromAbove` (`IdrOps.td:71`, `:110`), and `program.nest<idr::FuncOp>()` (`Pipeline.cpp:92`) is the nesting F2 describes. **W6** is answered in §3.2.
- **§5.1 F3 / §3's 98c6315c (the context's lock): bears here only through the context's construction.** The context is made with threading off and handed the pool (`Compile.cpp:178-179`), upstream's pattern; nothing in this subsystem reads a mutable type. No `TransientScope` exists (§2.6).
- **§5.1 G2 (actions and debug counters): holds.** 26 tagged transforms are actions (`Actions.h:31-63`); idris-mlir installs MLIR's action handler (`Run.cpp:293-299`) but deliberately no debug counter (`Main.cpp:66-68`), which idris-mlir-opt keeps (`Actions.h:4-6`). The solver layer's units (§5.1 design 3) would join the same mechanism; the profile of §5 is built on it.
- **§5.2 H1 (verifier parallel over isolated children): holds**, for the functions of the program on a recursive verify (§2.3).
- **§5.2 H3 (a module pass re-verifies everything): holds, and is worse than stated.** After a nested group the program's own verifiers still run, non-recursively (`Verifier.cpp:313-315, 376-380`): every function group pays the program's three single-threaded whole-program walks (§2.3) though it touched only functions. Up to 26 such runs per compilation (§2.3, *by reading*).
- **§5.2 H5 (symbol checks in `verifySymbolUses`): holds** for calls (`Call.cpp:29`); the root lookup in `ProgramOp::verifyRegions` is one `lookupSymbolIn` (`Func.cpp:106`).
- **§5.2 M11 (the levers): holds in part.** Nesting is used for 7 of the 26 passes and groups on the program; 21 `markAllAnalysesPreserved` and 13 `markAnalysesPreserved` sites exist (*measured*: `grep -rn markAllAnalysesPreserved lib | wc -l`, likewise), but upstream's symbol-dce never marks anything preserved, even when it erases nothing (pinned `lib/Transforms/SymbolDCE.cpp:45-83`), nor does the canonicalizer when it changes nothing (`lib/Transforms/Canonicalizer.cpp:86-92`): each of the 3 symbol-dce and 6 canonicalize runs re-verifies what it ran on whatever it did. Two small upstream patches (U-a, U-b in §4).
- **§5.2 E2 (non-convergence must not refuse): holds.** `canonicalize()` keeps upstream's default of not testing convergence (`Pipeline.cpp:28-32`; `Canonicalizer.cpp:89-90`); the comment at `Pipeline.cpp:153-165` argues why the lowering passes' 10 rounds cannot leave an op the conversion needs.
- **§5.3 D1 (two pools): refuted for us.** One pool (§2.5).
- **§5.3 M8 (each mutex checked): done for this subsystem** in §4 (DP-34, DP-35, DP-53).
- **§5.3 M10, E5 (`cl::opt` globals, no static constructors): holds.** The driver's options are file-scope `cl::opt`s (`Options.cpp:44-158`), so are the trace's (`Profile.cpp:63-69`) and idris-mlir-opt's `--idr-contracts` (`idris-mlir-opt.cpp:36-40`); `llvmZones` is a static object with a constructor (`Profile.cpp:197`).
- **§5.4 F16 (verification off in production): refuted for us.** Release verifies after every pass (§2.2), and offers no way not to.
- **§5.4 F17 (an option selecting between two implementations): holds once.** `--runtime` accepts the archive or the prepared runtime, two read paths behind one option (`ReadRuntime.cpp:349-368`, `Runtime.h:95-113`); DP-41.
- **§5.4 design 8 (mechanical enforcement): holds in part.** Our warnings (`CMakeLists.txt:344-361`) lack `-Wthread-safety`, `-Wcovered-switch-default`, `-Wsuggest-override` and `-Werror=global-constructors`; clang-tidy runs as a preset (`CMakePresets.json:31-39`), not as a test.
- **§5.5 D.11, D6 (PCH): refuted premise.** No PCH, because "ccache cannot cache" one (`CMakeLists.txt:40-41`, `bootstrap.sh:265-269`); §5.5 D6 cites LLVM's own `-Xclang -fno-pch-timestamp` for ccache (`HandleLLVMOptions.cmake:1458-1466`, *read* by that lane), and ccache documents PCH support under `sloppiness=pch_defines,time_macros` (*recalled*). DP-59.
- **§5.5 D8 (hardening, `llvm::Error` in the driver): holds in part.** Extensive hardening is on in every configuration (`CMakeLists.txt:326`); the driver reads its command line into `llvm::Expected<Invocation>` (`Options.cpp:252`), but carries its other failures as diagnostics at `UnknownLoc` (14 sites, §4 DP-26) and one `std::variant<Object, Failed>` (`Artifacts.cpp:183-189`).
- **§5.6 D2 (no fixed-point pipeline): holds** (`Pipeline.cpp:61-197` has no loop).
- **§5.6 E1 (Flang nests everything): we nest 7 of 26** (§2.2).
- **§5.7 L2 ("upstream first": `int-range-optimizations` nested per function, 3 s against 30 s module-wide):** our only per-value range work runs program-wide in idr-narrow (`Pipeline.cpp:135`) and per function only after lowering (idr-narrow-lanes, `:152`).
- **§5.8 B9 (a function pass may read its ancestors, not its siblings): decides the target design (§5).** It permits a nested function pass to read the program's table (`ProgramOp::getTypes`) and the program's cached analyses, and forbids reading a callee's body or signature.
- **§5.8 B10, EF3 (verifiers local; whole-function invariants as passes, run by instrumentation if needed): holds in part.** `verify::function` is per function (good) but the program's verifier does whole-program walks (§2.3).
- **§5.9 A2 (the order as data, reasons beside entries): holds in spirit, not in representation.** The reasons are comments beside C++ statements; the order is held twice and the copies disagree (§2.4).
- **§5.9 A3, design 6 (footprint per pass, a first-class report): absent** (§2.6).
- **§5.11 A2, A3, C1, C2: absent** (§2.6); the compiler's allocator is the system's (§2.6), so a footprint record can read the platform's counters directly.
- **0003, target lane:** "one target machine recipe" still open (`Target.cpp:66-67`, `Run.cpp:194-195`); "driver errors sit at `UnknownLoc`" still open (14 sites); "`make compile OUT=` keeps only the basename" still open (`tools/compile.sh:40`); "no stack probes" open (lane 12's lowering, a target-entry fact here).

### 3.2 Wave-2 questions in this subsystem, answered by ID

- **§5.1 W6 (every per-function pass anchored on the functions?): no.** Seven function passes are nested on `idr.func` (rc-cells, structure-loops, tail-loops, two canonicalize, two CSE); after lowering, eleven on `func.func`. Per-function work inside program passes: idr-deduplicate (`EliminateDuplicateFunctions.cpp:101,152`), idr-defunctionalize (`Defunctionalize/Pass.cpp:138`), idr-effects' analysis (`Analysis/Effects.cpp:63`), idr-optimize (`ReadySet.cpp:35`, `Waves.cpp:337`), idr-rc-stack via Reuses (`Reuses.cpp:276`), idr-rc-grades (`Grades.cpp:41,54`), idr-rc-exclusive (`Exclusive.cpp:50-53`), idr-narrow (`Narrow.cpp:168-171`), the recursion analysis (`Recursion.cpp:30`); after lowering, idr-lower (`Lower.cpp:220`), idr-tail-calls (`TailCalls.cpp:148`, `TailCallPlan.cpp:97`), idr-returned-arguments (`ReturnedArguments.cpp:139-141`). Each is a candidate for "decide in a program analysis, apply in a nested group" (§5, T1); B9 decides which (a step that adds or erases functions stays a program pass).
- **§5.1 W1 (V, B, P, F per pipeline point): not counted; how.** No built compiler here. Upstream's `print-op-stats` (registered in idris-mlir-opt through `registerAllPasses`, `idris-mlir-opt.cpp:44`) counts ops by name at any prefix of `--idr-pipeline`; values, blocks and regions per op need a counting pass (a `Statistic`-only analysis pass; §5, T6).
- **§5.1 W5 (attributes created on a hot path), for this subsystem: none found.** The verifier's `AttrTypeWalker` (`Func.cpp:66-76`) creates nothing; the trace's details are `std::string`s (`Profile.cpp:79-86`). SCCP's baseline is not on the pipeline.
- **§5.2 W3, last clause (a whole-module walk of ours per pass): yes, three**, `ProgramOp::verify`, `verify::program`, and its `TypeGraph` (§2.3), after every program pass and every nested group.
- **§5.2 W7 (measure the verifier; count module passes):** counted, by reading: 19 program passes, 7 program adaptors, 10 module passes (§2.2); measured with no rebuild as the difference between `-mlir-timing` rows and `--profile-actions-to` spans (§2.3), or with `idris-mlir-opt -verify-each=0 --idr-target --idr-pipeline` against the default (MlirOptMain's option, `lib/Tools/mlir-opt/MlirOptMain.cpp:190-193`; idris-mlir has none). Not run: no binary (rule 1).
- **§5.2 W8 (bytecode on a hot path): yes.** The frontend writes `<base>.mlirbc` (`Artifacts.h:79-80`, `Artifacts.cpp:69`), which the driver parses (`Run.cpp:270`); what goes in it as text is lanes 01 and 03's.
- **§5.2 W9 (passes that change nothing mark all preserved): ours mostly yes** (21 sites), upstream's symbol-dce and canonicalize no (§3.1).
- **§5.3, every mutex and `parallelFor` (this subsystem's):** `Outcome` (one lock, low traffic: a diagnostic, a statistic per pass run), `StatisticsInstrumentation` (a lock and a map entry per pass run, every function of every group), `Zones` (a lock and a map lookup per pipeline begin and end, only while tracing); all `parallelFor`s are MLIR's on the context's pool (§2.5).
- **§5.4, "whether release builds verify after every pass today": yes**, with no option to stop it in idris-mlir (§2.2); its cost is unmeasured.
- **§5.4, "every option or flag that selects between two implementations": `--runtime`** (DP-41); `--idr-contracts` adds a check and selects no implementation.
- **§5.5, the build:** 294 units, all of which include MLIR's core directly or through `IdrDialect.h` (§2.7); the compiling clang is stage 2 with assertions (`bootstrap.sh:1028`); ccache yes, PCH no; no `-ftime-trace` of our own build exists, and the stale ninja log is the only baseline (§2.7).
- **§5.6 W-E3 (analyses computed by more than one pass):** `TypeGraph` is built by the program verifier after every pass (`Verify/Program.cpp:266`), outside the `AnalysisManager` (0003's item, still open); `Layouts` likewise by `recycles` (`:104`).
- **§5.6 W-E4 (facts in discardable attributes):** the frontend's refusals arrive as the module's discardable `refusals` attribute (`Run.cpp:226-239`); the target is upstream's discardable `#llvm.target` and DLTI attributes (upstream's design); the program's stage is an inherent property (`IdrOps.td:74`).
- **§5.6 W-E5 (budgets and caps in the pipeline):** canonicalize's 10 rounds (never fails), the lowering passes' 10 rounds (never fails, argued at `Pipeline.cpp:153-165`), the schedule's cleanup 10 rounds with failure suppressed (`Schedules.cpp:76`, `:110`), the inlining budget into large callers, 2^12 LLVM instructions (`Target.h:111-118`, `LinkRuntime.cpp:128-139`), the bin size 2^15 (`Target.h:104-109`); none becomes a failure. Wall-clock limits exist only in scripts (`tools/self.sh:58-64`, `Makefile:123`, `:316`), as AGENTS.md's test timeouts.
- **§5.7, the stage-1 counts:** not counted here (no binary); W1's answer says how.
- **§5.8, "how the grade verifier runs": as op and region verifiers**, run by the pass manager after every pass (`IdrOps.td:60-66, 81-82, 167`, `Func.cpp:98-118`); per function in parallel for `verify::function`, single-threaded for the program's (§2.3).
- **§5.9 Q-W7, §5.10 W5 (the grade verifier's cost per pass, one linear walk?):** the per-function part is a walk per function per verify; the program part is three walks per program verify (§2.3); unmeasured.
- **§5.11 wave-2 3 (snmalloc as the compiler's malloc; what `peak_memory` reads):** no (§2.6); `ru_maxrss` from `wait4`, resident size (`tools/host.sh:127-150`).
- **§5.11 wave-2 8 (attributes created per function; a `TransientScope`):** none of this subsystem's passes creates per-function attributes; no `TransientScope` (§2.6). The program passes' own creation is the other lanes'.
- **§5.11 wave-2 9 (the action profile written incrementally?): the action profile yes** (flushed per event, `ActionProfiler.cpp:55-60`); **the time trace no** (at exit, `Profile.cpp:208-215`); `-mlir-timing` no.

## 4. Issues

Every row is *read* at the cited lines unless marked. "Owner" names the lane whose document owns the content when this lane only owns the scheduling.

### 4.1 The pipeline

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| DP-01 | `Pipeline.cpp:61-197`; `Passes.td:47-48`; `harness/lib/differential.sh:15-60` | list | The order and nesting are C++ statements; held again as `Passes.td`'s record order, which claims to be the pipeline's and is not (effects/knots, frames/accumulate swapped, §2.4), and from which `IdrPassStages.txt` is generated; the harness re-parses `--dump-pass-pipeline` with `awk`. | One record list in TableGen is the pipeline (§5 T2): order, nesting from each pass's anchor, reasons as fields; a generator emits `buildPipeline`'s body, the registration and the tests' table. The swapped copy goes. |
| DP-02 | `Pipeline.h:66-71`; 0004 §8 | rederivation | The stage chain (each `requires` equal to the previous `sets` or `any`) is checked per pass at run time and never for the pipeline as a whole. | TableGen `assert` over the record list with `!foldl` (§5.3 E1): a pipeline whose chain breaks does not build. The run-time check stays at the tool boundary (a fixture run at the wrong stage), where it is essential. |
| DP-03 | `Pipeline.cpp:62-135` | upstream | 19 passes anchored on `idr.program`, 7 nested: every program pass re-verifies all functions and runs the program's three single-threaded walks (§2.3). | "Decide in a program analysis, apply in a nested group" (§5 T1) wherever B9 allows; ods-Q6's evidence. |
| DP-04 | `Pipeline.cpp:92,110,115,38,132` + `Verifier.cpp:313-315,376-380` | state | Each nested group ends with the program's own verifiers (non-recursive verify still runs `verifyInvariants` and `verifyRegionInvariants`), three whole-program walks per group; single-pass groups (structure-loops, rc-cells, tail-loops) pay it for one function pass. | Coalesce adjacent groups where order allows; make the program's own verifiers per function (DP-07, owner 01/03). |
| DP-05 | `Pipeline.cpp:49,84,106` | upstream | Upstream symbol-dce never marks analyses preserved, even with nothing erased (pinned `SymbolDCE.cpp:45-83`): three full program verifies per compile regardless. | U-a: `upstream/<bug>/llvm.patch`, `markAllAnalysesPreserved()` when `numDCE == 0`, with a test; plan: a `[mlir]` PR. |
| DP-06 | `Pipeline.cpp:28-32` (6 uses: `:93,116,167,181`, inner of idr-optimize) | upstream | Upstream's canonicalizer never marks analyses preserved when nothing changed (`Canonicalizer.cpp:86-92`): every run re-verifies its op. | U-b: read `applyPatternsGreedily`'s `changed` out-parameter and preserve all when false; upstream PR. |
| DP-07 | `Func.cpp:56-89` (owner 03); `Verify/Program.cpp:253-297` (owner 01) | rederivation | After every program pass and group: every op's types and attributes walked for undeclared data types; every call walked for effects; the type graph rebuilt; recycles walked with a fresh `Layouts`. Facts that change only where the table or a signature changes are re-derived where nothing did. | The membership check per function in `verify::function` (reading the parent's table is allowed, B9) or unrepresentable (types naming an entry by index, §5.8 DS3.1); table facts in `DataTableAttr`'s verifier, once per instance (§5.2 H2); `TypeGraph`/`Layouts` from the `AnalysisManager` (0003). The scheduling half is this lane's; the content is lanes 01 and 03's. |
| DP-08 | `Pipeline.cpp:91-95,114-118,166-168,180-182` | rederivation | Canonicalize and CSE over every function as cleanup after program passes that changed some (MLton E3: the normal form is run by each pass over what it changed). | Lanes 04 and 09 decide the normalizer; the pipeline keeps a group only where a pass leaves garbage, measured by its statistics. |
| DP-09 | `Pipeline.cpp:28-32`; `:153-165` | budget | The greedy driver's 10 rounds, convergence untested; the lowering passes' rounds argued harmless. Never refuses. | Holds (AGENTS.md); keep, with the argument beside the record (DP-01). |
| DP-10 | `Pipeline.cpp:34-50, 199-213` | ladder | `addRc` and the registered `idr-rc` pipeline: a second entry into a slice of the order; the anchor decided by comparing the manager's anchor name with `ProgramOp::getOperationName()` (`:210-212`). | A named slice of the one record list (DP-01), nested by the generator from anchors; the string compare goes. |
| DP-11 | `Exclusive.cpp:50-55`; `Commit.cpp:153-183`; `Ownership.h:67`; `Passes.td:12-13` | ods | idr-rc-commit is a `PassWrapper` built with references to the parent's solve, symbol table and statistic, run by `runPipeline`; declared in no `.td`, against `Passes.td`'s own rule; no timing row of its own (0003). | Declared in `Passes.td`, reading the solve with `getCachedParentAnalysis` (§5.1 F1) from a cached `Exclusivity` analysis; scheduled in the pipeline as a nested group, not by `runPipeline` (owner 08 for the solve). |
| DP-12 | `Narrow.cpp:166-171`; `ReturnedArguments.cpp:133-145` | upstream | Two more passes nest their own pipelines with `runPipeline` instead of the pipeline nesting them; each pays the parent's verify twice (inner group, then outer pass). | Pipeline-level nesting, the analysis preserved by the deciding pass and read cached by the nested one. |
| DP-13 | `Optimize/Component.cpp:85-97`; `Passes.td:255-256` | state | idr-optimize's per-node inner pipeline verifies the function after each of its five passes, for every node (owner 09). | Evidence for Q-M2 and Q-O5; one verify at the node's end is what the contract needs if the inner steps are one transform. |
| DP-14 | `Pipeline.h:53-61` | rederivation | `StagedPass<ModuleOp>` refuses a module of more than one program though `ProgramOp::verify` already refuses a second program (`Func.cpp:56-62`); only the zero-program case is new information. | Keep the zero case (a tool given an empty module); the "more than one" arm cannot fire after verification: delete it. |
| DP-15 | `Pipeline.h:30-77` | cpp | `StagedPass` is right as a base (stages as template parameters, the anchor by `if constexpr`); its `runOnProgram` is virtual, MLIR's pass hierarchy being open. | Keep; it is the place a pass's stages become a type. |

### 4.2 The driver

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| DP-16 | `Register.cpp:135-150` | list, dead | `registerCompilerPasses` lists "each upstream pass the pipeline adds" by hand: it registers remove-dead-values (`:139`), which 16005000 removed from the pipeline, and not the canonicalizer, which the pipeline adds six times. | Generated from the pipeline's records (DP-01); the dead registration goes now. |
| DP-17 | `Register.cpp:75-86` | upstream | The dialects the pipeline's passes load are listed by hand beside every pass's `dependentDialects`. | `OpPassManager::getDependentDialects(registry)` on the built pipeline (upstream). The external models (`:95-129`) stay a list: upstream has no dependent-model declaration. |
| DP-18 | `lib/CMakeLists.txt:119-186`; `Transforms/CMakeLists.txt:516-556` | list | A third copy of the pipeline's dialect and pass set, as link libraries ("What the compiler registers", `:142-143`). | Upstream's `MLIR_DIALECT_LIBS`/`MLIR_CONVERSION_LIBS`/`MLIR_EXTENSION_LIBS` properties as mlir-opt links them; static linking pulls only what is referenced, so a superset costs link time, not size (*conjecture*, to measure). |
| DP-19 | `Options.cpp:100-125, 260-279`; `Options.h:66-69`; `Main.cpp:38-56` | ladder | `Action` (6 cases) and `Question` (4 cases) are one set twice, each with its switch, `PrintX` mapped to `X`. | One `constexpr` table of print actions (flag, description, answer), `cl::values` and the answer both read from it; the second enum and one switch go. |
| DP-20 | `Options.cpp:162-171` | list | `driverOptions[]` and `frontendOnly[]` list the driver's options by hand, beside their definitions. | `cl::OptionCategory` (upstream): each option names its category; "read only by this action" is a category query. Both arrays go. |
| DP-21 | `Options.cpp:154-158`; `idris-mlir-opt.cpp:36-40, 64-69`; `Run.cpp:145-149` | list | `--idr-contracts` defined twice with a copied description; the instrumentation set installed twice. | One `idr::instrument(PassManager &, Checks)` and one option definition in the library both tools link. |
| DP-22 | `Options.h:45`; `Options.cpp:247`; `Run.cpp:145` | cpp | `PassChecks { Verifier, Contracts }`: `Verifier` names what always happens. | Essential (a test-only check); rename the case for what it adds (`Contracts`) against none. |
| DP-23 | `Main.cpp:86-88` | list | Defaults injected as argv strings (`--align-all-functions=6`, `--align-all-nofallthru-blocks=6`, `--mlir-print-op-on-diagnostic=false`). | Function alignment as the `alignment` of each lowered function (IR, lane 12); the rest is LLVM's interface: essential. |
| DP-24 | `Run.cpp:226-239, 276-278`; `IdrBase.td:68-70` (`refusals`) | attribute | The frontend's refusals arrive as a discardable attribute on the module, read before the module's kind is parsed. | A third kind of handoff module in `moduleKindOf`'s variant (`Refused`, its refusals as ops or as the module's one op), so the kind is parsed once and no fact sits in a discardable attribute (with lanes 15, 16). |
| DP-25 | `Run.cpp:79-124` | cpp | `moduleKindOf` returns `variant<Handoff, Lowered>` (a parse at the boundary, right) but chooses its predicate by a `bool handsOff` and a `Holds{function_ref, literal}`. | Fold into DP-24's three-way parse: one `match` over the module's first op. |
| DP-26 | `Run.cpp:164,180,252,282`; `Compile.cpp:90`; `Artifacts.cpp:141,173,254,265`; `Prepare.cpp:69,120`; `ReadRuntime.cpp:352`; `LinkRuntime.cpp:110`; `Schedules.cpp:271` | rederivation | 14 errors at `UnknownLoc` where the file they concern is known (0003). | `FileLineColLoc` of the path (line 0) at each; the "pipeline failed and reported no error" site keeps the module's location. |
| DP-27 | `Target.cpp:61-94`; `Run.cpp:182, 194-195`; `Optimize.cpp:37-46` | rederivation | Two machines (idr-target's `LLVM::detail::getTargetMachine` with default options for the vector width; `idr::target::machine` for code) and the layout written twice (DLTI by idr-target, `setDataLayout` from the machine after translation): 0003's "one target machine recipe", open. | idr-target builds `idr::target::machine` (one recipe), and the translated module's layout is DLTI's, checked against the machine's DLTI form as 0003 says; `Run.cpp:194-195`'s reset goes. |
| DP-28 | `Run.cpp:138-167`; `idris-mlir-opt.cpp:64-69`; `Profile.cpp:105-175`; `Run.cpp:290-299`; `Compile.cpp:155-157` | upstream | Three recorders of the same pass spans: our time-trace zones (`Zones`), MLIR's action profiler (every `PassExecutionAction`, pattern application and tagged action), and `-mlir-timing`; the first two write Chrome traces of different content (zones include the verifier, actions exclude it, §2.3). | One trace (§5 T4): MLIR's action framework the source of every MLIR span, an observer of ours writing LLVM's time trace; analyses, LLVM passes and driver phases into the same trace; `Zones`' pass hooks go. |
| DP-29 | `Run.cpp:189-190, 201-202, 214-215, 221-222, 268-269`; `Compile.cpp:108-109, 118-119, 154-157` | list | Every driver phase opened twice, an `IDR_ZONE_IN` and a `TimingScope` of the same name. | One RAII `Phase` (one name, both recorders) or one recorder (DP-28). |
| DP-30 | `Compile.cpp:117`; `Artifacts.cpp:81`; `Options.cpp:238` | cpp | `get_if`/`holds_alternative` on closed sums (`Product`, `Source`): a question whose answer is half used (§5.3 I3). | One `match`/`std::visit` per use; the link is the `Executable` alternative's step. |
| DP-31 | `Verdict.h:69-110` | state | `Outcome` under one mutex; statistics keyed by `"<pass>.<statistic>"` strings. | Essential: the report is text for a reader; the lock sees a few events per pass run. Keep. |
| DP-32 | `Outcome.cpp:114-160` | upstream | Statistics read per pass run under a lock into a `DenseMap<Pass *, …>`, because MLIR merges its copies' statistics only where it prints them (`:118-122`). | U-e: a public accessor of merged pass statistics (upstream `PassManager`), then one read at the end; or keep (one lock per pass run). |
| DP-33 | `Outcome.cpp:51-63` | cpp | A switch naming `DiagnosticSeverity`. | Keep (one place); no upstream stringify (*recalled*). |
| DP-34 | `Artifacts.cpp:183-189, 300-306` | cpp | `variant<Object, Failed>` with a string where the driver's vocabulary is `llvm::Expected` (§5.5 D8). | `llvm::Expected<Object>` per slot, joined with `llvm::joinErrors` on the calling thread. |
| DP-35 | `Runtime.h:42-43`; `Prepare.cpp:95-115`; `foreign/idr/CMakeLists.txt:191-194, 210-213`; `ReadRuntime.cpp:253-277` | per-target | Where the prepared runtime's bitcode lives (`InObject` on ELF, `BesideObject` on Mach-O) is the entry's fact, branched on in four places (a C++ switch, two CMake branches, a section-or-file fallback read). | One home on every target (beside the object), deleting the entry fact, the enum, the switch, both CMake branches and the section path; or keep if one file on ELF is essential (new question NQ5). |
| DP-36 | `Runtime.h:95-113`; `ReadRuntime.cpp:291-368`; `Prepare.cpp:132-146`; `LinkRuntime.cpp:111-119` | rederivation | `variant<Archived, Prepared>`: a compile accepts either runtime kind (two read paths behind `--runtime`, §5.4 F17); preparing refuses `Prepared` at run time. | Two functions with one result each: `readArchive` for `--prepare-runtime`, `readPrepared` for a compile; a compile given an archive is a usage error at the boundary; the variant, the generic visits and the refusal branch go. |
| DP-37 | `ReadRuntime.cpp:109-114` | cpp | `sameTarget` compares triple fields by hand. | Keep: it states which fields matter (OS version included), which `Triple::isCompatibleWith` does not. |
| DP-38 | `LinkRuntime.cpp:128-139`; `Target.h:111-118` | budget | Calls into the runtime from a function past 2^12 LLVM instructions stay calls (0781ed93: 121 s to 11 s). Program units; never refuses. | Holds AGENTS.md; keep. |
| DP-39 | `Compile.cpp:166-179`; `Stack.h:64-74`; `Runner.cpp:44`; `Threading.cpp:81-93`; `PINS.md:585-605` | per-target | The reserved stack covers the main thread only; function passes, the parallel verifier and code generation run on pool threads with LLVM's default stacks (8 MiB on Darwin, the pthread default on Linux), so PIN(mlir-recursion)'s workaround does not hold off the main thread and the depth a pass survives differs by OS. `PINS.md:595` says 2^40 where `Runner.cpp:44` reserves 2^36. | U-d: a stack size in `llvm::ThreadPoolStrategy` (`llvm::thread` takes one, `StdThreadPool` passes none), or a `ThreadPoolInterface` whose workers run on the runtime's runner (NQ4). The stale PIN text corrected. |

### 4.3 The target

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| DP-40 | `Schedules.cpp:303-308`; `ScheduleOps.td:19` | ods | `VectorizeLanesOp::getEffects` written by hand (consume, produce, modify payload). | Upstream's `FunctionalStyleTransformOpTrait` with `MemoryEffectsOpInterface` (`TransformInterfaces.h:1324-1345`) declares exactly that; the method goes. |
| DP-41 | `Schedules.cpp:286-298`; `ScheduleOps.td:33` | ods | The op takes any handle and skips a payload op that is no `linalg.generic` (`dyn_cast` + `continue`), though its script matches only generics (`:101`). | A typed handle, `Transform_ConcreteOpType<"linalg.generic">`, makes another payload unrepresentable (the interpreter checks payloads against handle types); the `dyn_cast` and the skip go. |
| DP-42 | `Schedules.cpp:140-148, 162-166` | rederivation | The vector width is looked up and validated per loop, though idr-target wrote it once. | Read once per function by the op's `apply`; an absent width is idr-target's bug, checked where it writes (keep the error at that boundary). |
| DP-43 | `Schedules.cpp:76, 110` | budget | The cleanup's 10 rounds, failure suppressed. Never refuses. | Holds; keep. |
| DP-44 | `Schedules.cpp:89-115, 262-273` | list | The schedule library is assembled from string pieces and parsed when the transform dialect loads. | Keep (text is MLIR's format for a transform script); a `.mlir` file in the source tree embedded at build time reads better (*conjecture*). |
| DP-45 | `Partition.cpp:234`; `Support/Scc.cpp` (owner 05) | upstream | The reference graph's components come from our SCC utility. | `llvm::scc_iterator` over a `GraphTraits` of the symbol graph (§5.3 B8). The partition itself is essential: upstream's `SplitModule` hashes into N parts and clones the module N times (pinned `SplitModule.cpp:216-229, 287`), while ours names bins by content and reads each lazily. |
| DP-46 | `Partition.cpp:199, 349`; `Extract.cpp:50` | cpp | `get_if`/`holds_alternative` on `Home` and the roles. | One `match` per use. |
| DP-47 | `Target.h:104-109`; `Partition.cpp:53-57` | budget | Bins of 2^15 instructions; program units; never refuses. | Holds; keep. |

### 4.4 Profiling and actions

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| DP-48 | `Profile.h:78` (15 call sites); `Profile.h:81` | dead | `IDR_ZONE_IN(name, subsystem)` discards `subsystem` (a Tracy leftover: 1e1a3827 added Tracy, d06ed15c left the time trace); `IDR_INSTANT` has no user (*measured*: `grep -rn IDR_INSTANT lib include tools`). | Delete the parameter and the macro; or the whole macro family under DP-28. |
| DP-49 | `Profile.cpp:63-69, 74, 197` | cpp | `cl::opt` globals, a global `tracedProc`, a static-constructed `llvmZones` (§5.3 E5). | The trace request read once into the `Invocation`; `Trace` owns its callbacks; no static constructor. |
| DP-50 | `Profile.cpp:105-175` | state | `Zones` takes a mutex and a `DenseMap` lookup by thread id at every pipeline's start and end while tracing (every nested group on every function). | A `thread_local` depth, or the presence of the thread's profiler (`getTimeTraceProfilerInstance()`); the map and the lock go. |
| DP-51 | `Profile.cpp:126-131, 140-144` | rederivation | Pass and analysis zones restate MLIR's `PassExecutionAction` spans. | DP-28. |
| DP-52 | `Profile.cpp:63-69, 208-215` | state | The time trace lives in memory and is written at exit: a run killed by the OS writes nothing (§5.11 A3, wave-2 9); at the default granularity 0 every span is kept, so the profiler's memory grows with the run (*conjecture*: millions of entries at stage 1). | Flush on the platform's pressure signal (§5.11 A3, oom-2) and at stage boundaries; footprint counters in the same trace (§5 T5). |
| DP-53 | 26 `static constexpr … tag = "idr-…"` in 20 files (*measured*: `grep -rn 'static constexpr.*tag = ' lib include`) | list | Action tags as string literals spread over the passes; some restate a pass argument (`idr-frames`). | Keep the strings (upstream's debug-counter format); declare each pass's tags in its `Passes.td` record so the tests and the Idris side read one list (owner 14 for the generator). |
| DP-54 | `Actions.h:52-63` | cpp | `perform<A>(op, function_ref<void()>)`. | Keep: `executeAction` takes a `function_ref` (upstream's API). |

### 4.5 The build, tools and scripts

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| DP-55 | `CMakeLists.txt:40-41`; `bootstrap.sh:265-273` | upstream | No precompiled header, on a premise §5.5 D6 refutes; ~294 units each parse MLIR's core (*measured*): about 7.5 CPU-minutes of headers per clean build at the host's 1.54 s per unit, about 2.1 with a PCH (*arithmetic* on §5.5 D.11). | `add_mlir_library(… PRECOMPILE_HEADERS …)` on `IdrIR` with `mlir/IR/pch.h`, our `IdrDialect.h` and ADT; `-Xclang -fno-pch-timestamp` and ccache's `pch_defines,time_macros` sloppiness; cxx-Q3. |
| DP-56 | `CMakeLists.txt:326`; `bootstrap.sh:971-996` | cpp | Extensive libc++ hardening on every C++ unit of ours in every configuration, the runtime (inlined into programs) included, set per unit through `CMAKE_CXX_FLAGS`; the pinned libc++ is built at its default mode. | cxx-Q4; with a PCH the mode must be per target anyway (§5.5 D6); as the bootstrap's `LIBCXX_HARDENING_MODE` it is one fact. Release unmeasured. |
| DP-57 | `bootstrap.sh:1022-1031, 1127-1132` | state | Stage 2, which our tools link and are compiled by, has `LLVM_ENABLE_ASSERTIONS=ON` and forced statistics: "release" idris-mlir runs MLIR with assertions and ABI-breaking checks, so every stage-1 measurement includes them. | New question NQ1; until answered, measurements say they include assertions. |
| DP-58 | `CMakeLists.txt:344-361` | cpp | No `-Wthread-safety`, `-Wcovered-switch-default`, `-Wsuggest-override`; `-Werror=global-constructors` would fire on the `cl::opt`s and `llvmZones` (DP-49). | Add `-Wthread-safety` (libc++'s mutex is annotated, §5.4 design 8) with `GUARDED_BY` on the three locked members; the others with the cutover's C++ (lane cxx). |
| DP-59 | `CMakePresets.json:15-49` | list | No preset records our own compile time (`-ftime-trace`), the baseline §5.5 D6.2 asks for. | A `trace` preset (Debug, `-ftime-trace`), or the typecheck build with it. |
| DP-60 | `foreign/idr/CMakeLists.txt:115-143` | list | Per-tool link lists by hand. | Keep (three tools); idris-mlir-opt and -reduce link everything by design. |
| DP-61 | `unittests/*.cpp` (e.g. `Cycles.cpp:113, 200`; `Constants.cpp:60, 82, 107, 129`) | state | Each test makes an `MLIRContext` with threading on, a thread pool per context (owner 19). | `MLIRContext(Threading::DISABLED)` where a test runs no parallel loop. |
| DP-62 | `tools/profile.sh:89-101` | list | The trace's totals aggregated by an inline Python program on the host's `python3`. | idris-mlir prints the totals itself (the trace's `Total` events are LLVM's), or a harness tool (owner 19). |
| DP-63 | `tools/self.sh:81-84, 123-124`; `tools/host.sh:127-150` | state | The self compile's record is `ru_maxrss` (resident, not what jetsam kills on, §5.11 K5) and `-mlir-timing` printed at exit; a killed stage-1 run leaves its peak and nothing of where it was. | The per-pass footprint record (§5 T5, oom-3); `--profile-actions-to` or the flushed trace on the stage-1 run. |
| DP-64 | `tools/compile.sh:40` | rederivation | `OUT` keeps only its basename (0003). | Pass `-o` through as given. |
| DP-65 | `Makefile:154-161` | — | `make build` configures and builds the preset; one CPU budget (`:107-112`). | Holds; no change. |

### 4.6 Upstream patches this lane proposes

| ID | where (pinned) | what | test | plan |
| --- | --- | --- | --- | --- |
| U-a | `mlir/lib/Transforms/SymbolDCE.cpp:45-83` | `markAllAnalysesPreserved()` when nothing was erased | a pass-manager test that counts verifier runs (an instrumentation) on a module symbol-dce leaves alone | `[mlir]` PR, small; precedent: CSE does it (`CSE.cpp:51`) |
| U-b | `mlir/lib/Transforms/Canonicalizer.cpp:86-92` | preserve all analyses when `applyPatternsGreedily` reports no change | as U-a | `[mlir]` PR |
| U-d | `llvm/include/llvm/Support/ThreadPool.h`, `ThreadPool.cpp:51` | a stack size in `ThreadPoolStrategy`, passed to `llvm::thread` | a unit test spawning a pool with a stack size and recursing past 8 MiB | `[Support]` PR |
| U-e | `mlir/include/mlir/Pass/PassManager.h` | a public read of merged pass statistics | unit test | `[mlir]` RFC (small) |

## 5. Target design

Seven changes, each in the skill's terms; then the order and the dependencies. Everything here is *conjecture* until built and measured; the evidence is §2 to §4.

### T1. Three kinds of step: decide, apply, restructure

**Representation.** The pipeline holds three kinds of step, and a pass is exactly one:
- *decide*: a pass on `idr.program` that computes a whole-program fact as a cached analysis (`getAnalysis<X>()`) and changes no op; it marks every analysis preserved, so the pass manager skips the verifier after it (`Pass.cpp:629-640`);
- *apply*: a nested group on the functions whose passes read the decision with `getCachedParentAnalysis<X>()` (§5.1 F1) and rewrite their own function whole (body, signature, the types at its call sites); each function is verified on its worker as its pass ends, and the program's own verifiers (names, every call's `verifySymbolUses`, the program's rules) run once, when the group ends, on a program every function of which is consistent;
- *restructure*: a pass on `idr.program` that adds or erases functions, sums or table entries (deduplicate's erasures, defunctionalize's sums and dispatch functions, specialization's clones, frames' run and resume, the accumulator and destination clones, symbol-dce, the lowering): §5.8 B9 forbids a function pass to change its siblings, so these stay program passes. This is the essential case (Brooks): changing the symbol table is the program's.

```text
idr.program( decide-grades,                       // analysis only: verifier skipped
             idr.func( apply-grades ),            // per function, parallel; program checked once at the end
             decide-exclusivity,
             idr.func( commit-exclusivity ),      // today's RcCommit, declared in Passes.td
             symbol-dce )                         // restructure
```

**What it deletes.** The hand-written parallel loops inside passes and their analyses (13 sites, §3.2, W6) where B9 allows, the two `runPipeline` nests (`Exclusive.cpp:50-53`, `Narrow.cpp:168-171`) and idr-returned-arguments' (`ReturnedArguments.cpp:139-141`), `RcCommit`'s constructor-handed state (`Commit.cpp:179`), and 4c87dcc5's failure mode: a program verified half-graded, between a pass that writes every signature and a pass that places every body.

**One line.** *Unrepresentable:* a nested pass that reads a sibling (it is handed its function and its parent's cached analyses, nothing else), and a program verified between "signatures changed" and "bodies changed" (a decide step changes nothing; an apply step changes each function whole). *Check moved to a boundary:* cross-function consistency, from after every pass to the end of each group.

### T2. The pipeline is one record list

**Representation.** A TableGen list of steps beside `Passes.td`, each a pass record (ours, or upstream's from `mlir/Transforms/Passes.td` and kin) with its options and its reason:

```tablegen
class Step<Pass p, string why, string opts = ""> {
  Pass pass = p;  string reason = why;  string options = opts;
}
defvar IdrPipelineSteps = [
  Step<IdrDeduplicate, "of each class of identical functions the rest see one">,
  Step<IdrDefunctionalize, "every later pass is first-order; the call graph sees every call">,
  Step<IdrKnots, "a knot of references is a cycle of the type graph">,
  // ...
  Step<Canonicalizer, "folds what the columns conversion leaves", "region-simplify=disabled">,
];
// The stage chain, checked where the list is written: each `requires`
// is the stage the steps before it left, or `any`.
assert !eq(!foldl("Higher", IdrPipelineSteps, at, s, /* next stage or "broken" */),
           "Lowered"), "the pipeline's stage chain breaks";
```

A generator (in idris-mlir-tblgen, lane 14) emits from it, once: the textual pipeline, nested by each pass's anchor (`::idr::FuncOp` under `idr.program`, `::mlir::func::FuncOp` under the module, consecutive steps of one anchor in one group), which `buildPipeline` hands to upstream's `parsePassPipeline` and `registerIdrPipeline` registers as `PassPipelineRegistration`; the registration of every upstream pass the list names; and the table the tests read in the pipeline's order (`IdrPassStages.txt`'s successor, which `harness/lib/differential.sh` then reads instead of parsing `--dump-pass-pipeline`).

**What it deletes.** `Pipeline.cpp:61-197`'s statements (their comments become `reason`s), `addRc` and the anchor comparison of the `idr-rc` registration (`Pipeline.cpp:34-50, 206-213`), `registerCompilerPasses`' hand list with its dead remove-dead-values and its missing canonicalizer (`Register.cpp:135-150`), `Passes.td:47-48`'s claim about record order, and the harness's `awk` reconstruction (lane 19). The dialect list (`Register.cpp:83-86`) goes too: `OpPassManager::getDependentDialects` on the built pipeline gives it.

**One line.** *Unrepresentable:* a pipeline whose stage chain breaks (it does not build), a function pass placed at program level or the reverse (nesting is computed from anchors), and a second copy of the order. *Check moved:* the stage chain from run time (`Pipeline.h:66-71`) to build time for the pipeline; the run-time check stays only at the tool boundary, where a fixture names one pass (essential).

### T3. Verification after every pass, priced by where each check lives

This lane does not decide ods-Q6, Q-M2 or Q-O5 (§6); it makes every option cheaper, by mechanisms:
- U-a and U-b (§4.6): symbol-dce and canonicalize preserve every analysis when they change nothing, so the verifier is skipped after them (`Pass.cpp:629-640`).
- T1: per-function verification on workers, the program's own once per group.
- The program's three walks (§2.3) moved to where their facts change (content lanes 01 and 03): data-type membership into each function's region verifier (parallel; reading the parent's table is allowed, B9) or made unrepresentable by types that name a table entry by index (§5.8 DS3.1); `effectsCovered` into `verify::function`, since it reads only the function's own calls' effects (`Verify/Program.cpp:61-79`); the table's own facts (a memo sum in a box, no type containing itself in place, no label past the higher stage) into the table attribute's verifier, which runs once per instance (§5.2 H2).
- The verifier made visible: T4 names its span after every pass.

**One line.** *Check moved to a boundary:* type-table facts from "after every pass" to "once, when the table is made"; cross-function facts to the end of each group. *Branch deleted:* none; the work moves.

### T4. One trace

**Representation.** MLIR's action framework is the one source of spans for MLIR work: every pass execution (`PassExecutionAction`, which wraps `runOnOperation` alone), every pattern application and every tagged transform is an action already (§3.1, G2). One observer of ours turns each action into a zone of LLVM's time trace, named by its tag, its detail the function `printTag` finds (`Actions.cpp:27-32`); one `PassInstrumentation` adds what actions do not cover: each analysis, and each pass's verifier, as the span from its action's end to `runAfterPass` (§2.3); LLVM's passes keep `llvmCallbacks`; each driver phase is one RAII `Phase` that opens the zone and the `TimingScope` under one name. Per-thread trace state begins and ends in the one pool wrapper of T6, not at each task's top.

**What it deletes.** `Zones`' pass and pipeline hooks with their lock and per-thread map (`Profile.cpp:105-175`), the `IDR_ZONE_IN` and `TimingScope` pairs (12 sites, DP-29), `IDR_ZONE_IN`'s unused parameter and `IDR_INSTANT` (DP-48), the `ThreadTrace` at task tops (`Artifacts.cpp:196`, `Component.cpp:253`, `Lower.cpp:221`, `Stack.h:50`), and the second Chrome-trace format as the documented method (0001's `--profile-actions-to`; upstream's option stays registered, unused by our scripts).

**One line.** *Unrepresentable:* a pass span recorded twice with different content (zones with the verifier, actions without), and a phase timed under two names. *Essential, kept:* the choice between a buffered trace (LLVM's, no lock per event, lost on `SIGKILL`) and a streamed one (MLIR's action profiler, a lock and a flush per event, about 1 GB a minute in idr-optimize per 0001): T5's pressure flush is what lets the buffered one survive; which to keep is a measurement (§8).

### T5. The compiler's memory as a record, never a gate

**Representation.** One platform function (runtime/Platform, lane 18; AGENTS.md puts OS calls behind it): the process's footprint now and its peak (macOS `task_info(TASK_VM_INFO)`'s `phys_footprint` and `ledger_phys_footprint_peak`; Linux the cgroup's `memory.current` and `memory.peak` when in one, else resident plus swap, §5.11 A2). One `PassInstrumentation` on the outermost manager records it after every program and module pass (not per function: sampled), into the trace (T4) and into the report as `footprint:` lines, apart from `statistic:` lines so that determinism checks, which compare statistics, ignore them. On the platform's pressure signal (libdispatch `CRITICAL`; a PSI trigger), the trace is flushed and one line names the pass, the function and the footprint (§5.11 A3).

**What it deletes.** Nothing; it replaces guessing (0001: `sample` against a run whose trace stops growing) and `ru_maxrss` as the run's only memory figure (`tools/self.sh:81-84`).

**One line.** *Unrepresentable:* a stage-1 run killed with no record of where it was. *Not a budget:* it stops nothing and refuses nothing (oom-2's reading; §6).

### T6. The driver: each fact parsed once, in its type

- **The module's kind**: `variant<Refused, Handoff, Lowered>` parsed once from what the module holds (DP-24, DP-25); the refusals stop being a discardable attribute. *Unrepresentable:* a module that is both refused and a program; *deleted:* `reemitRefusals`' attribute read and the `handsOff` bool.
- **The runtime**: `readPrepared` for a compile, `readArchive` for `--prepare-runtime` (DP-36). *Branch deleted:* the variant, two generic visits and the run-time refusal of a prepared runtime given to `--prepare-runtime`.
- **The target**: one machine recipe and DLTI's layout as the translated module's (DP-27; 0003). *Rederivation deleted:* the second machine and the reset from constants.
- **Options**: categories instead of hand arrays (DP-20); print actions as one table (DP-19); one `--idr-contracts` and one `instrument` function for both tools (DP-21). *Deleted:* `driverOptions[]`, `frontendOnly[]`, the `Question` enum and one switch, the second option definition.
- **Locations**: every driver error at the file it concerns (DP-26). *Rederivation deleted:* 14 `UnknownLoc`s where the path is in hand.
- **The pool**: one `ThreadPoolInterface` of ours over the context's threads, each worker on a reserved stack (as the main thread is, PIN mlir-recursion) and owning its thread's trace (T4); or upstream's `StdThreadPool` with U-d's stack size (DP-39, NQ4). *Unrepresentable:* a pass whose recursion depth depends on whether it ran on the main thread or a worker, or on the OS's default stack.
- **The bitcode home**: one form on every target if the owner agrees (DP-35, NQ5). *Branch deleted:* four branches on a per-target fact.
- **Small C++**: `match` instead of `get_if` (DP-30, DP-46), `llvm::Expected` in code generation's slots (DP-34), `thread_local` instead of a locked map (DP-50, if T4 keeps any per-thread depth).

### T7. The build

- A precompiled header on `IdrIR` (DP-55), after a `-ftime-trace` baseline of today's build (DP-59, §5.5 D6.2); the premise against it is refuted (§3.1). *Measured, not assumed:* the per-unit header cost.
- The hardening mode as one fact (the bootstrap's `LIBCXX_HARDENING_MODE`, or one per target once a PCH fixes macros), its release cost measured (DP-56, cxx-Q4).
- `-Wthread-safety` with `GUARDED_BY` on the three locked members of this subsystem (DP-58).
- Stage 2's assertions stated in every measurement until NQ1 is answered (DP-57).

### Order inside the subsystem, and dependencies

1. **Measure first** (T5, T4's verifier span, and the census pass of §8): small, additive, and what every later step is judged by (§3's "trace it, don't guess"; owner's Q4). Depends on lane 18 for the platform function.
2. **U-a, U-b** (§4.6): independent, immediate.
3. **T2** (the record list and its generator): depends on lane 14's generator and Q-llvm-5; lands with an unchanged order, so its first check is that the generated pipeline equals today's `--dump-pass-pipeline` text.
4. **T1**, lane by lane, as each lane's pass redesign lands: lane 08 first (idr-rc-commit already is an apply step), then 11 (narrow-words), 10 (returned arguments), 09 (idr-optimize's inner pipeline), 06 (defunctionalize's per-function conversion). Each split is a change of the record list (T2), checked by its stage chain.
5. **T3** with lanes 01 and 03 (the verifier's content and the table's representation).
6. **T6** and **T7**: independent of the rest; T6's pool depends on lane 18 (the reserved-stack runner) or on U-d.

## 6. Evidence for the owner's questions

No answers: what this subsystem's code and history say, by question.

**ods-Q6 (re-verify all functions after a module pass, or make nesting a rule).**
- Today the program stage runs 19 program passes against 7 function passes in 5 groups (§2.2). Every program pass that does not preserve all analyses re-verifies every function (in parallel) and runs the program's three single-threaded whole-program walks; every group runs those three walks once more at its end (§2.3; `Verifier.cpp:313-315, 376-380`). *By reading*: up to 26 runs of the walks per compilation.
- About a dozen passes already do per-function work by hand, in 13 parallel loops (11 files) and three `runPipeline` nests (§3.2, W6); B9 (§5.8) bounds which of them could nest: a pass that adds or erases functions cannot.
- 4c87dcc5 is the history's one collision between nesting and verification: idr-rc-place, split out as a nested pass after idr-rc-grades wrote every signature, left the program half-graded at a verify boundary and failed every program with a reference; the fix folded the two back into one program pass. Calls check their callee only in `verifySymbolUses` (`Call.cpp:29`), which runs at the program's boundary, so a group that rewrites each function whole under a decision computed beforehand (T1) would not meet that collision (*conjecture*, from the code).
- Upstream's symbol-dce and canonicalizer never skip the verifier, even unchanged (§3.1; U-a, U-b).
- `unittests/Verify.cpp:1-7` states the property kept by every option: the pass manager verifies the program after a program pass.
- The cost is unmeasured; §8 M1 and M2 measure it without a code change.

**Q-M2 (full verification in release, or the grade check always and MLIR's verifier at phase boundaries).**
- Release verifies after every pass and idris-mlir has no way to turn it off (§2.2). The release binary also links MLIR built with assertions (`bootstrap.sh:1028`, DP-57), so "release" already pays MLIR's own development-time checks.
- "The grade check, cheap if it reads only types" holds for one of three parts: what lives in types is checked once per type (§5.2 H2); `verify::function` walks each function (parallel); the program's part walks the whole program single-threaded (§2.3).
- idr-optimize verifies a function after each of its five inner passes for every node (`Component.cpp:85-97`, DP-13).
- What verification after every pass has caught: 4c87dcc5 (every program with a reference, after idr-rc-grades), and on the stage-1 run "failed verification 1088 times over one bug" (Reuses meeting a matched box's field twice, `proposals/0001-self-host.md:93-101`).
- A split by build type would be a behaviour chosen by the build; by option, a behaviour option, which `Passes.td:4-5` and `Main.cpp:66-68` exclude by principle.

**Q-O5 (keep the grade verification after every pass; its cost a measured budget of the verifier).**
- The contract is met today at §2.3's cost; its time is inside every pass's `-mlir-timing` row and outside its action span (`Pass.cpp:604-650`), so the budget can be measured per pass from one run (§8 M1), and named in every trace by T4.

**QL4 (byte-identical output for any thread count).**
- The code claims it in four places: `--num-threads` "output bytes do not depend on it" (`Options.cpp:140-149`), "two compiles of one module are the same bytes either way" (`Compile.cpp:169-175`), bins "a function of the module's content" (`Target.h:127-130`), idr-optimize "the same at every thread count" (`Passes.td:272-273`).
- The harness tests it: compilations at 1, 3, 5 and 13 threads, a drawn count and a second process, compared byte for byte at every step (`harness/testutils.sh:46-47`, `harness/lib/determinism.sh:10-25`).
- The mechanisms here: bins named by a hash of their members' names and sorted by name (`Partition.cpp:104-117, 297-312`); largest-first scheduling of bins changes only the order of work (`Artifacts.cpp:283-296`); statistics summed over every copy's runs, so independent of the split (`Outcome.cpp:114-124`); diagnostics of a parallel group replayed after it (`Outcome.cpp:68-71`).
- What would break it if added: footprint figures and trace content in a compared output (T5 keeps them apart).

**Q-llvm-6 (every solver run with one thread and with many, solutions compared).**
- Only whole-pipeline determinism is tested (above); no analysis is compared alone. The harness's mechanism (`determinism.sh`) and idris-mlir-opt's `--mlir-disable-threading` are where a per-solver comparison would run (the solvers are lanes 05 to 08's).

**cxx-Q3 (precompiled headers now; modules not in P0).**
- No PCH, on the premise that ccache cannot cache one (`CMakeLists.txt:40-41`; `bootstrap.sh:265-273`, which turns LLVM's own off too); §5.5 D6 refutes the premise (LLVM's `-Xclang -fno-pch-timestamp`); our ccache sloppiness is `include_file_ctime,include_file_mtime` only (`bootstrap.sh:261`), and would need `pch_defines,time_macros` (*recalled*).
- 294 units, all of which include MLIR's core directly or through `IdrDialect.h`, itself carrying the 38,361-line `IdrOps.h.inc` (§2.7). The stale typecheck log shows 7.26 s mean wall per unit under parallel load, `Driver/Run.cpp` 40.1 s (§2.7, *measured*, weak).
- Modules were tried and taken out: 4cfce768 ("C++ as named modules, one concept per file, each module its own library"), then 1e1a3827 ("headers and .cpp with no C++ modules"); `CMAKE_CXX_SCAN_FOR_MODULES OFF` (`CMakeLists.txt:320-321`).

**cxx-Q4 (the libc++ hardening mode for debug and test; release measured or unchecked).**
- Extensive, in every configuration, Release included, on every C++ unit of ours and the runtime's (`CMakeLists.txt:323-326`), set per unit through `CMAKE_CXX_FLAGS`; the pinned libc++ is built at its default (no `LIBCXX_HARDENING_MODE`, `bootstrap.sh:971-996`). `PINS.md:845-858` (clang-libcxx) records it as the stand-in for `_GLIBCXX_ASSERTIONS`.
- The runtime, inlined into every program, uses `std::array`/`std::span` only in its platform layer (*measured*: `grep -rl 'std::span\|std::array\|std::vector\|std::string_view' runtime`, three files), so the mode's reach into programs' hot paths is small (*conjecture*). Release cost unmeasured.

**oom-2 (the compiler running out: a crash, not a refusal; budgets in program units).**
- Every budget of this subsystem is counted in program units and never fails: canonicalize's rounds, the schedule's rounds, 2^12 instructions for inlining into a large caller, 2^15 per bin (§3.2, W-E5). Wall-clock limits exist only in scripts (`tools/self.sh:58-64`; `Makefile:123, 316`), as AGENTS.md's test timeouts.
- Today a compiler out of memory is LLVM's handler (installed by `InitLLVM`, `Main.cpp:59`): "LLVM ERROR: out of memory" and `abort()` (§5.11 C1), an exit by signal, apart from the refusal status 3 and the internal status 1 (`Options.h:26-29`); the verdict table has no row for it (`Verdict.h:35-57`). Under overcommit the OS's kill comes first, and then nothing is written: the trace and `-mlir-timing` are written at exit (§2.6).

**oom-3 (a footprint record per pass, and which measure).**
- None exists (§2.6). The tools use the system's allocator (no override in `runtime/`), so `mallinfo2`/`malloc_zone_statistics` would count the heap correctly, but jetsam kills on `phys_footprint`, which only `task_info` reports (§5.11 K5). `tools/self.sh` records `ru_maxrss` (`tools/host.sh:127-150`).
- `PassInstrumentation` is the place (T5); the report already folds per-pass data (`Outcome.cpp:125-160`), but determinism checks compare its statistics, so a footprint must be apart from them.

**Q2 (does 0001's S3 rerun stop until P0's plan is approved).**
- `tools/self.sh` runs stage 1's pipeline half on the release preset with no time limit (`self.sh:59-63, 123-124`; `Makefile:265-268`), recording `ru_maxrss` and `-mlir-timing` at exit; 0001's method adds `--profile-actions-to` and `sample` by hand (`proposals/0001-self-host.md:102-111`). A run killed by the OS leaves its peak and the streamed action profile, nothing else (§2.6).
- What a rerun would measure is the state models P0 replaces; what P0's designs need from it is §8's numbers (verifier share, census, footprint per pass), most of which today's binary can give (§8 M1-M4).

**Q4 (who runs the release idris-mlir on the stage-1 module for P0's measurements).**
- No build exists in this checkout but the typecheck one (`build/typecheck`); `make self` builds the release preset (`Makefile:265-268`).
- What a release measurement includes, beside the pipeline: MLIR and LLVM with assertions (`bootstrap.sh:1028`), verification after every pass (§2.2), libc++'s extensive hardening (`CMakeLists.txt:326`). §8 lists what each run needs to record.

### New questions for the owner

- **NQ1.** Stage 2, which every build of idris-mlir links and is compiled by, has `LLVM_ENABLE_ASSERTIONS=ON` (`bootstrap.sh:1022-1031`). Should P0's stage-1 measurements (Q4) be taken on an LLVM without assertions (a second stage-2 build, or assertions off for the one toolchain, which the dev build then loses), or stated as including them?
- **NQ2.** The pipeline as one TableGen record list (order, reasons, options), its stage chain asserted in TableGen and its nesting computed from anchors, generating the textual pipeline, the registrations and the tests' table (T2)?
- **NQ3.** Decide, apply, restructure (T1) as a rule for every lane's passes, with §5.8 B9 deciding what must be a restructure?
- **NQ4.** The context's workers on reserved stacks like the main thread (PIN mlir-recursion), through a pool of ours, or upstream's `StdThreadPool` given a stack size (U-d)? Today a pass's recursion limit depends on the thread it runs on and the OS (DP-39).
- **NQ5.** The prepared runtime's bitcode in one home on every target (beside the object), removing a per-target fact branched on in four places (DP-35)?
- **NQ6.** For stage-1 runs, one buffered time trace flushed on memory pressure (T4, T5), or MLIR's streamed action profile (a lock and a flush per event; about 1 GB a minute in idr-optimize per 0001)?

## 7. Deletion list

By file and symbol; each goes in the change that makes it dead (hard cutover). "If NQn" marks a deletion that waits on the owner.

- `foreign/idr/lib/Transforms/Pipeline.cpp`: `buildPipeline`'s statements (`:61-197`, their comments kept as the records' `reason`s), `addRc` (`:35-50`), the `idr-rc` registration's anchor comparison (`:206-213`), `canonicalize()` (`:28-32`, a step option). (T2)
- `foreign/idr/include/idr/Transforms/Pipeline.h:53-61`: the "more than one program" arm of `StagedPass<ModuleOp>` (verified away). (DP-14)
- `foreign/idr/include/idr/Transforms/Passes.td:47-48`: the claim that record order is the pipeline's. (T2)
- `foreign/idr/lib/Driver/Register.cpp`: `registerCompilerPasses`' hand list (`:137-149`), `registerRemoveDeadValuesPass()` (`:139`, dead today); the dialect list (`:83-86`). (DP-16, DP-17)
- `foreign/idr/lib/CMakeLists.txt:142-181`: the hand list of dialect, extension and conversion libraries of `IdrDriver`. (DP-18)
- `foreign/idr/lib/Driver/Options.cpp`: `driverOptions[]`, `frontendOnly[]` (`:162-171`), the second definition of `--idr-contracts`'s text; `include/idr/Driver/Options.h:66-69`: `Question`; `lib/Driver/Main.cpp:38-56`: `answer`'s switch (one table). (DP-19 to DP-21)
- `foreign/idr/tools/idris-mlir-opt.cpp:35-40, 64-69`: the duplicate option and instrumentation setup. (DP-21)
- `foreign/idr/lib/Driver/Run.cpp`: `reemitRefusals`' attribute read (`:231-239`) and `moduleKindOf`'s `Holds`/`handsOff` (`:87-98`), replaced by the three-way parse; the triple and layout reset (`:194-195`); the paired `TimingScope`s and zones (`:189-222, 268-269`). (DP-24, DP-25, DP-27, DP-29)
- `foreign/idr/lib/Driver/Compile.cpp:108-109, 118-119`: paired phase instrumentation. (DP-29)
- `foreign/idr/include/idr/Driver/Runtime.h:95-113` and `ReadRuntime.cpp:349-368`: `variant<Archived, Prepared>`; `Prepare.cpp:141-145`: the refusal of a prepared runtime. (DP-36)
- If NQ5: `Runtime.h:36-43` (`BitcodeHome`, `runtimeBitcodeHome`), `Prepare.cpp:95-115` (the switch), `foreign/idr/CMakeLists.txt:96-98, 191-194, 210-213` (the definition and both branches), `CMakeLists.txt:114-119, 178, 262` (the entry fact), `ReadRuntime.cpp:253-277` (the section path). (DP-35)
- `foreign/idr/lib/Target/Target.cpp:64-71`: the second target machine. (DP-27)
- `foreign/idr/lib/Target/Schedules.cpp:303-308` (`getEffects`), `ScheduleOps.td:19` (`DeclareOpInterfaceMethods<MemoryEffectsOpInterface>`), `Schedules.cpp:289-291` (the `dyn_cast` and skip). (DP-40, DP-41)
- `foreign/idr/lib/Support/Profile.cpp:105-175` (`Zones`' pass and pipeline hooks, its mutex and map), `:74` (`tracedProc`), `:197` (`llvmZones` as a static); `include/idr/Support/Profile.h:78` (`subsystem`), `:81` (`IDR_INSTANT`). (DP-48 to DP-51)
- `idr::profile::ThreadTrace` at task tops: `Artifacts.cpp:196`, `Optimize/Component.cpp:253`, `Conversion/Lower.cpp:221`, `Support/Stack.h:50` (into the pool, T6).
- `foreign/idr/lib/Transforms/Ownership/Exclusive.cpp:50-53` and `Commit.cpp:179-183` (`createRcCommit(solved, symbols, counter)`); `Narrow/Narrow.cpp:166-171`; `Tail/ReturnedArguments.cpp:139-141`: `runPipeline` nests, replaced by pipeline nesting. (DP-11, DP-12; content lanes 08, 10, 11)
- The hand `parallelFor` loops of §3.2 (W6) that B9 lets nest, each in its lane's change. (T1)
- `foreign/idr/lib/IR/Verify/Program.cpp:61-79` (`effectsCovered`, into `verify::function`) and `:266-296` (the table checks, into the table's verifier); `lib/IR/Func/Func.cpp:56-89` (`ProgramOp::verify`'s walk). Lanes 01 and 03 own these. (T3)
- `harness/lib/differential.sh:15-60` (the `awk` reconstruction of the pipeline; lane 19). (T2)
- `tools/profile.sh:89-101` (the Python aggregation; lane 19). (DP-62)
- `tools/compile.sh:40` (the basename). (DP-64)
- Corrected, not deleted: `PINS.md:595` (2^40, where `Runner.cpp:44` reserves 2^36).

## 8. Risks, unknowns, measurements needed

**Risks.**
- **T1's soundness rests on op verifiers that read no sibling.** Calls do it right (`Call.cpp:29`). Any op `verify()` that looks a symbol up would fail on a group's intermediate state. Lane 03 checks every `lookupSymbolIn`/`lookupNearestSymbolFrom` in an op's `verify()`.
- **More groups, more program checks.** Each group ends with the program's own verifiers (DP-04); until T3 moves the three walks, T1 can cost more than it saves. Measure before and after.
- **Worker stacks** (DP-39): a nested pass that recurses over a deep constant on a worker dies with a bare `SIGSEGV`, not the tools' named error. Unmeasured on stage 1.
- **The generator** (T2): upstream passes' records must be reachable from our TableGen includes (`mlir/Transforms/Passes.td`, `mlir/Conversion/Passes.td`, the dialects' `Passes.td`); options must round-trip through `parsePassPipeline`.
- **Determinism**: footprint and trace data must stay out of every compared output (T5).
- **PCH** hides missing includes and fixes macros for every unit of a target (§5.5 D6).
- **Upstream acceptance** of U-a, U-b, U-d, U-e: carried as patches meanwhile (AGENTS.md), each with its report, test and plan.
- **The time trace's own memory** at granularity 0 on stage 1 (DP-52, *conjecture*): measure before it becomes the method.

**Unknowns.** The verifier's share of each pass on stage 1 (W7); V, B, P, F and regions per op at each stage (W1); the footprint per pass (oom-3); what assertions in MLIR cost on stage 1 (NQ1); our build's header cost per unit with and without a PCH; whether idr-optimize's per-node verification dominates its time (DP-13).

**Measurements, each with its command (none run here: no binary, rule 1).**
- **M1, the verifier per pass, with today's binary:** `idris-mlir --num-threads=N -mlir-timing --profile-actions-to=stage1.actions.json build/self/stage1/idris-mlir-front.mlirbc -o /tmp/x`; per pass, its `-mlir-timing` row less the sum of its `PassExecutionAction` spans is its verifier and instrumentation (§2.3).
- **M2, the whole pipeline's verifier:** `idris-mlir-opt --idr-target --idr-pipeline -verify-each=0 -mlir-timing stage1.mlirbc -o /dev/null`, against `-verify-each=1` (MlirOptMain's option).
- **M3, the census (W1):** `idris-mlir-opt --pass-pipeline='builtin.module(idr-target, idr.program(<steps up to a stage>), print-op-stats)'` for op counts at each stage boundary; values, blocks and regions per op need a statistics-only pass (T5's companion, an `IdrPass` of role analysis).
- **M4, the footprint without code:** on macOS, `/usr/bin/time -l idris-mlir …` prints the peak memory footprint beside `ru_maxrss` (*recalled*); on Linux, the run inside a cgroup (`systemd-run --scope -p MemoryAccounting=yes`) and its `memory.peak`.
- **M5, the build's header cost:** the typecheck build with `-ftime-trace` per unit (DP-59), then with a PCH on `IdrIR`.
- **M6, hardening in release:** the bench (`make bench`) with the runtime and the tools at `_LIBCPP_HARDENING_MODE_NONE` against extensive (lane 18 for programs).
- **M7, worker stacks:** PIN mlir-recursion's reproducer (a constant nested 10,000 deep) in a function, canonicalized nested on functions with threads on and with `--mlir-disable-threading`.

## 9. Sources read

**Required reading, in order:** `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md` (whole); `proposals/0000-mlir-native.md` (whole, lines 1-11,141, in chunks); `proposals/0003-facts-once.md` (whole); `audits/p0/README.md` (whole).

**This subsystem, read line by line:**
- `foreign/idr/lib/Transforms/Pipeline.cpp`; `include/idr/Transforms/Pipeline.h`; `include/idr/Transforms/Passes.td` (whole, descriptions skimmed for anchors, stages, statistics).
- `foreign/idr/lib/Driver/{Artifacts,Compile,LinkRuntime,Main,Options,Outcome,Prepare,ReadRuntime,Register,Run}.cpp`; `include/idr/Driver/{Artifacts,BuiltRuntime,Compile,Main,Options,Report,Runtime,Verdict}.h`.
- `foreign/idr/lib/Target/{Target,Optimize,Extract,Partition,Schedules}.cpp`, `include/idr/Target/{Target.h,ScheduleOps.td}`.
- `foreign/idr/lib/Support/{Profile,Actions}.cpp`, `include/idr/Support/{Profile,Actions,Stack}.h`; `include/idr/InitIdr.h`.
- `foreign/idr/tools/{idris-mlir,idris-mlir-opt,idris-mlir-reduce}.cpp`.
- `CMakeLists.txt`, `CMakePresets.json`, `foreign/idr/CMakeLists.txt`, `foreign/idr/RuntimeDigest.cmake` (head), `foreign/idr/lib/CMakeLists.txt`, `lib/{Support,IR,Analysis,Target}/CMakeLists.txt`, `lib/Transforms/CMakeLists.txt` (structure, `:491-556`), `unittests/CMakeLists.txt`, `unittests/Main.cpp`, `unittests/Verify.cpp` (head), the other unit tests by `grep`.
- `tools/self.sh`, `tools/profile.sh`, `tools/compile.sh` (head), `tools/host.sh:110-150`, `tools/bootstrap.sh:240-285, 960-1060, 1118-1140, 1325-1345`, `Makefile:100-330`.

**Read for context, outside the subsystem:** `include/idr/IR/IdrOps.td:40-115`, `IdrBase.td:68-70`; `lib/IR/Func/Func.cpp:40-140`, `Func/Call.cpp:29-31`; `lib/IR/Verify/Program.cpp:1-40, 250-308`; `lib/Transforms/Ownership/{Exclusive,Commit}.cpp` (heads and nests), `Narrow/Narrow.cpp:150-180`, `Tail/ReturnedArguments.cpp:125-150`, `Optimize/Component.cpp:60-110`; `include/idr/Transforms/Contracts.h`, `lib/Transforms/Contracts/Contracts.cpp` (by `grep`); `runtime/Start/Runner.cpp` (by `grep`), `runtime/CMakeLists.txt:120-160`; `harness/lib/differential.sh:1-60`, `harness/testutils.sh:40-50`, `harness/lib/determinism.sh` (head); `harness/README.md:70-82`; `PINS.md:585-615, 817-875`; `proposals/0001-self-host.md:90-125`, `proposals/0004-tests.md:140-146, 315-330`.

**Pinned tree (`.toolchain/llvm-project`, 7208ba24):** `mlir/lib/Pass/Pass.cpp:590-690, 1020-1030`; `mlir/include/mlir/Pass/PassManager.h:225-230, 270-280, 490-500`; `mlir/lib/Pass/PassManagerOptions.cpp` (options); `mlir/lib/Tools/mlir-opt/MlirOptMain.cpp:185-195, 590-595`; `mlir/lib/IR/Verifier.cpp:252-470`; `mlir/lib/Transforms/{Canonicalizer.cpp:86-105, CSE.cpp:30-60, SymbolDCE.cpp:45-100}`; `mlir/lib/Debug/Observers/ActionProfiler.cpp:1-80`; `mlir/include/mlir/Dialect/DLTI/DLTIAttrs.td` (by `grep`); `llvm/lib/Support/{Threading.cpp:78-95, ThreadPool.cpp:45-55, TimeProfiler.cpp}` (by `grep`); `llvm/include/llvm/Support/thread.h:75-90`; `llvm/lib/Transforms/Utils/SplitModule.cpp` (by `grep`), `llvm/include/llvm/Transforms/Utils/SplitModule.h`.

**History:** `git log --oneline` of every path above; `git show` of 16005000 (remove-dead-values out, `Register.cpp` left), 4c87dcc5 (the half-graded program), 28274bd3 (contracts in the driver), 1c38fff5 (one target description), 74dd457c (one target machine, earlier), 0781ed93 (the inlining budget), d06ed15c (the profiler without Tracy), 1e1a3827 (Tracy pinned; C++ modules removed), 4cfce768 (C++ modules, earlier).

**Measured (commands in place):** `wc -l` of every file; `grep -c 'IdrPass<"'`; constructor-by-constructor `grep` of `Pipeline.cpp` and `Run.cpp`; `grep -rn 'parallelFor\|failableParallelForEach\|parallelForEach'`; lock and atomic `grep`; `markAllAnalysesPreserved`/`markAnalysesPreserved` counts; `UnknownLoc` sites; action tags; zone macro uses; unit counts and MLIR includes; `IdrOps.h.inc` size; the typecheck build's `.ninja_log` (last entry per object, `awk`).
