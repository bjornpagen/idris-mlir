# U06: the pipeline, the driver and the options that go

## Permitted outcome

1. **Mandatory.** `Passes.td` is C12's registry, row for row: the new
   `IdrOptimize`, `IdrStructureLoops`, `IdrBufferize` and `IdrConstants`; `IdrContify`
   declared from `Optimize.h`; `IdrRc` and `IdrDemand` without options;
   `IdrDefunctionalize` without `numClosures`; `IdrExpect` with `tensor`
   and `scf` among its dialects and no property list in its description;
   the eight defs of ## Delete gone; every description restated to what the
   pass does after the cutover (0004 §4, 0003 §5, §7, §8).
2. **Mandatory.** `Pipeline.h` and `Pipeline.cpp` are C12 §3: one
   `idr::buildPipeline(mlir::OpPassManager &)` adding the 26 rows in order,
   and `idr::registerIdrPipeline()`. Nothing in either takes an option.
3. **Mandatory.** The driver keeps exactly C12 §4's command line. The four
   driver options ## Delete names, their uses and the per-pass dump
   instrumentation are gone, and so is the debug counter's registration in
   idris-mlir (D46). `run` builds one pass manager with the profile's
   zones, `idr-target` and `buildPipeline`; it recognizes a refusal by
   C04's accessor (D42); it parses the handoff with `tensor` and `scf`
   added (C22) and C05's flow models registered; after O3 it calls C13's
   code generation entry, and the link passes C13's objects.
4. **Mandatory.** idris-mlir-opt and idris-mlir-reduce register C05's
   flow models and, through C13's call, the schedule library on their
   registry; idris-mlir-opt's
   manager carries only the profile's zones. `tools/idris-mlir.cpp` is
   unchanged.
5. **Mandatory.** `tools/compile.sh`'s usage text names only options
   idris-mlir has.
6. **Mandatory.** `Profile.h`, `Profile.cpp`, `Actions.h` and `Actions.cpp`
   keep their API (C12 §5); their comments stop naming the rounds and say
   that a task on a pool begins its share of the trace with `ThreadTrace`,
   and that a debug counter skips actions only in idris-mlir-opt.
7. **Consumer adaptations.** `ReadRuntime.cpp:161`'s refusal begins with
   C04's `idr::refusalHead(idr::Rule::Runtime)`. `Prepare.cpp` and
   `LinkRuntime.cpp` change only where C13 changes a declaration they call
   (`emit`, `Artifacts.h:75-77`, at `Prepare.cpp:148`); otherwise they stay
   as they are.

## Owner / exclusive writes

Roots as ownership.json gives them: `INC` = `foreign/idr/include/idr`,
`IDR` = `foreign/idr/lib`, `TL` = `foreign/idr/tools`.

- `IDR/Driver/Compile.cpp`: the frontend's arguments, the link, `compile`.
- `IDR/Driver/Dump.cpp`: **deleted**.
- `IDR/Driver/LinkRuntime.cpp`: a consumer adaptation only (item 7).
- `IDR/Driver/Main.cpp`: the command line's registration, the `--print`
  answers.
- `IDR/Driver/Options.cpp`: the option objects.
- `IDR/Driver/Prepare.cpp`: a consumer adaptation only (item 7).
- `IDR/Driver/ReadRuntime.cpp`: a consumer adaptation only (item 7).
- `IDR/Driver/Run.cpp`: the pass manager, the verdict, stage 13 and the
  call into C13.
- `INC/Driver/Compile.h`: `run`'s new signature; `DumpAfterEachPass` deleted.
- `INC/Driver/Main.h`: unchanged unless a comment names a deleted option.
- `INC/Driver/Options.h`: the option declarations.
- `INC/Driver/Report.h`: unchanged (C12 §5).
- `INC/Driver/Runtime.h`: unchanged (C12 §5).
- `IDR/Transforms/Pipeline.cpp`: the one pipeline.
- `INC/Transforms/Pipeline.h`: registration and `buildPipeline`.
- `INC/Transforms/Passes.td`: the registry.
- `INC/Support/Profile.h`, `IDR/Support/Profile.cpp`: comments only.
- `INC/Support/Actions.h`, `IDR/Support/Actions.cpp`: comments only.
- `TL/idris-mlir.cpp`: unchanged.
- `TL/idris-mlir-opt.cpp`: the manager's instrumentation, the schedule
  library.
- `TL/idris-mlir-reduce.cpp`: the schedule library.
- `tools/compile.sh`: its usage comment.

New files: none. Deleted: `IDR/Driver/Dump.cpp`.

**Excluded:**
- `IDR/Driver/Artifacts.cpp`, `INC/Driver/Artifacts.h`, `IDR/Target/`,
  `INC/Target/` (U07): the partition, code generation per bin, the
  archive for `-c`, `emit`, the schedule library and its entry points,
  `idr-target`.
- `INC/Transforms/Canonicalize.h`, `INC/Support/Scc.h`,
  `IDR/Support/Scc.cpp`, `IDR/Transforms/Optimize/`,
  `INC/Transforms/Optimize.h`, `IDR/Transforms/Simplify/`,
  `INC/Transforms/Simplify.h`, `IDR/Transforms/Inline/` (U03): the inner
  per-function pipeline, the instrumentation of the rounds and its
  definition.
- Every pass header and unit C12 §2 names, each its owner's: U02, U03,
  U04, U05, U08, U09, U10, U11, U12, U16, U17. `IDR/Transforms/Demand/` and
  `INC/Transforms/Demand.h` are U08's.
- `compiler/src/IdrisMLIR/Frontend/` (U14): the frontend's half of the
  shape-breaking test hook.
- `tests/` (U17, U18), `bench/README.md` and `bench/run.sh` (U18).
- Every `CMakeLists.txt` the coordinator owns; `foreign/idr/lib/CMakeLists.txt`,
  which holds `IdrDriver`'s source list and is in no lane's writes
  (report it; do not edit it).
- `tools/*.sh` other than `tools/compile.sh` (coordinator).

## Read first

- `contracts.md` (or, until it exists, `contracts/`): C12 whole; C13 (the
  code generation entry, the `Artifacts` members, the schedule library's
  registration and entry point); C04 (the refusal accessor); C20 (the
  frontend's command line); C22 (the emitted module's dialects).
- 0004 (`proposals/0004-compile-time/README.md`): §1 lines 75-99; §4 lines
  670-1024; §5.3 item 6 and §5.4, lines 1160-1197; §6 lines 1229-1328; §10
  lines 1465-1529 (the L4 row, 1493); D2, D17, D42, D45, D46, lines
  1536, 1577-1580, 1779-1825.
- 0003 (`proposals/0003-typed-apl/README.md`): §5 lines 848-894; §7 lines
  957-1039; §7.1 lines 1041-1100; §8 lines 1125-1260; §17 stage 1, lines
  1619-1654.
- The lane's files: `foreign/idr/include/idr/Transforms/Passes.td` whole;
  `lib/Transforms/Pipeline.cpp` whole; `include/idr/Transforms/Pipeline.h`
  whole; `lib/Driver/Run.cpp:62-141` (the verdict, the leave-out check, the
  manager), `:143-202` (stage 13 and the codegen call), `:218-308` (the
  context, the handler, the action handler); `lib/Driver/Options.cpp`
  whole; `include/idr/Driver/Options.h` whole; `lib/Driver/Main.cpp:84-178`;
  `lib/Driver/Compile.cpp:28-113`; `include/idr/Driver/Compile.h:47-92`;
  `lib/Driver/Dump.cpp`; `tools/idris-mlir-opt.cpp:43-88`;
  `tools/idris-mlir-reduce.cpp`; `tools/compile.sh:4-18`;
  `include/idr/Support/Profile.h:44-56, 78-81`; `lib/Support/Profile.cpp:1-26,
  209-219`; `include/idr/Support/Actions.h:1-7`; `lib/Driver/Prepare.cpp:70-150`.
- The reasons to carry into `Pipeline.cpp`'s comments:
  `lib/Transforms/Simplify/Simplify.cpp:97-109` (the removal's
  `canonicalize = false`) and `Simplify/Round.cpp:24-77`.
- The current headers of every pass (`include/idr/Transforms/*.h`,
  `include/idr/Conversion/Passes.h`, `include/idr/Target/Target.h`), to
  see which `GEN_PASS_DECL` each holds today.
- Upstream (`M` = `.toolchain/build/llvm-project/mlir`):
  `M/lib/Dialect/Bufferization/Transforms/EmptyTensorElimination.cpp:208-228`;
  `M/include/mlir/Dialect/Transform/Transforms/Passes.td:64-109`;
  `M/include/mlir/Transforms/Passes.td:127-160` (remove-dead-values);
  `M/lib/Debug/CLOptionsSetup.cpp:83-92` and `M/lib/Debug/DebugCounter.cpp:113-120`
  (an unregistered counter installs no handler);
  `M/lib/Tools/mlir-opt/MlirOptMain.cpp:700-710`;
  `M/lib/Pass/PassManagerOptions.cpp:61`; `M/include/mlir/IR/Diagnostics.h`
  (`DiagnosticArgument`).
- Research: `sources/notes/compile-pipeline/casework-audit.md:18-23, 56-57`;
  `sources/notes/compile-pipeline/upstream-mlir-llvm.md:154-156`.

## Fixed decisions

- C12 is the authority for every `def`, every row of the pipeline, the
  command line and the kept declarations. This part only says how to get
  there.
- One pipeline. `buildPipeline` takes the manager and nothing else; no
  row depends on an option, an environment variable or what the module
  holds (0003 D30). The groups are written directly with
  `pm.nest<idr::FuncOp>()` and `pm.nest<mlir::func::FuncOp>()`, a fresh
  nest per group, so the adaptor runs each group over the functions in
  parallel.
- `eliminate-empty-tensors` runs on the module (C12 §3's reason), before
  `idr-bufferize`.
- The vectorization group's interpreter gets its entry point from C13's
  constant; Pipeline.cpp holds no schedule name of its own.
- The driver's verdict keeps today's statuses (`Options.h:52`): any error
  diagnostic fails the compilation; one that C04's accessor calls a
  refusal makes the status `rejected` (3); any other is internal (1). The
  handler reads the diagnostic's data, never its text.
- The module after each pass is `-mlir-print-ir-tree-dir`'s, which
  `applyPassManagerCLOptions` already gives (`Run.cpp:118`); the driver adds
  no instrumentation for it.
- Stage 13 stays in `Run.cpp` as today (`Run.cpp:164-198`: translate, link
  the runtime, retarget, internalize everything but `main`, O3). Then one
  call into C13 partitions and generates code per bin; `Run.cpp` writes no
  object itself. The one thread pool is the context's (`Run.cpp:232-239`),
  sized by `threadBudget()`; `Run.cpp` makes no second one and passes C13's
  entry exactly what its signature asks.
- `run` becomes `int run(Artifacts &artifacts, mlir::TimingScope
  &rootTiming)` (C12 §5), so the outputs are named by, and recorded in,
  the `Artifacts`.
- Without `-c`, `Compile.cpp`'s link passes the pinned clang the objects
  C13's `Artifacts` names, in its order, then the runtime, `-o` and the
  link flags; with `-c` there is no link (C13's code writes the archive).
- idris-mlir registers no debug counter; `mlir::tracing::DebugConfig`'s
  options and the action handler stay, so `-log-actions-to` and
  `--log-actions-tags` work as today.
- `Profile.h` and `Actions.h` keep every declaration; only comments change.
- A comment says why the code is as it is now; none names a deleted
  mechanism, a document, a decision or a lane.

## Inputs

- C12 itself (this lane's), for the shape of everything below.
- The pass headers C12 §2 names, each holding its `GEN_PASS_DECL`: C05 and
  C06 (`Defunctionalize.h`, U02), C07 and C08 (`Optimize.h`, `Identity.h`,
  `Canonicalize.h`, U03), C09 (`Specialize.h`, U04), C10 (`Effects.h`, U05),
  C11 (`StructureLoops.h`, U11), C13 (`Target.h`, U07), C14 (`Ownership.h`,
  `Stack.h`, `Demand.h`, U08), C15 (`Bufferize.h`, U12), C16
  (`Conversion/Passes.h`, U10), C23 (`Deduplicate.h`, U16), C24
  (`Expect.h`, U17); U09's `Tail.h` and `Narrow.h`.
- C13: the vectorization entry point's name; the call that puts the
  schedule library on an `mlir::DialectRegistry`; the code generation
  entry `run` calls after O3; the `Artifacts` members `Compile.cpp`'s link
  reads; whether `emit` (`Artifacts.h:75-77`) stays for `Prepare.cpp`.
- C04: `idr::refusalRule(mlir::Diagnostic &)`, which says whether an
  error is a refusal, and `idr::refusalHead(idr::Rule)`, the one writer of
  a refusal's words.
- C05: `idr::registerFlowInterfaceExternalModels` (`include/idr/IR/Flow.h`,
  U02), which every tool includes and calls
  on the registry it reads a module with.
- C20: the frontend's command line (`--prefix`, `--package-path`, `-p`,
  `--no-prelude`, `--core`, `-o`, the source).
- C22: the dialects the emitted module holds.

## Outputs

- C12: `foreign/idr/include/idr/Transforms/Passes.td` (every `def`, its
  argument, anchor, statistics, dependent dialects and the one option of
  `idr-expect`); `foreign/idr/include/idr/Transforms/Pipeline.h`
  (`idr::registerIdrPasses`, `idr::buildPipeline`,
  `idr::registerIdrPipeline`); `foreign/idr/lib/Transforms/Pipeline.cpp`
  (the order); the driver's command line; the kept declarations of
  `Report.h`, `Options.h`, `Compile.h`, `Runtime.h`, `Profile.h` and
  `Actions.h`.
- Consumers: U02, U03, U04, U05, U07, U08, U09, U10, U11, U12, U16 and U17
  derive their passes from these `def`s; U03 builds idr-optimize's inner
  pipeline from `createIdrIdentity` and `createIdrRedirect`; U03 and U07
  open zones and wrap pool tasks in `ThreadTrace`; U04 uses `Actions.h`;
  U07 uses `Report.h`, `Options.h` and `Compile.h`; U17 and U18 name passes
  by their arguments and run `--idr-pipeline`; U18's spec checks read the
  registry and the command line.

## Implement

**`Passes.td`.** Rewrite to C12 §2. Keep the file's header comment's rule
(each pass is built by its generated constructor; a pass on `idr.func`
touches nothing outside its function) and replace the list of nested steps
with C12 §2's sentence. Descriptions, each in the repository's voice:
- `idr-deduplicate`: one of each class of private functions with the same
  type, facts and body stays, the lexicographically smallest; merging is
  bottom-up over the call graph, so a class whose members call merged
  functions merges in the same run; every use of the others names the one
  kept (0004 §4 stage 3).
- `idr-defunctionalize`: the label solve over the one flow interface, with
  no unknown element; the effects summary computed right after it; every
  key a sum, boxed only on a cycle of captures; each apply a dispatch whose
  arms are direct calls; the conversion per function (0004 §2.4, §4 stage
  4). The one refusal is a boxed sum past the header's tags.
- `idr-effects`: C10's description, word for word.
- `idr-constants`: C10's description, word for word.
- `idr-contify`: a function that always returns to the same place becomes
  blocks of the one function it returns into, MLton's contification on
  first-order code, before idr-optimize (0004 §4 stage 5); keeps the
  existing sentence about `total`.
- `idr-optimize`: 0004 §4 stages 6 to 9 as they stand there: the ready set
  over the components of upstream's call graph; each function once, after
  its callees are final; call-site effects written when the caller becomes
  ready; MLton's decisions (a leaf of at most 40 ops; `(calls - 1) * (size
  - 60) <= 320`; nothing on a cycle of calls; `calls` frozen when the pass
  starts) with calls inlined in call-site order while the caller stays at
  or under 10,000 ops; the inner pipeline run once (idr-identity,
  canonicalize, cse, idr-redirect, int-range-optimizations, the constants
  solve); the bounded local loop; specialization nodes keyed by callee and
  static pattern, made once and named from the key, at most 1,024 distinct
  requests of one owner per node, a request past that left a call; erased
  originals removed afterwards in module order. Numbers: 40, 60, 320 kept
  (0004 §6, "Kept"); 10,000 (D25); 1,024 (D39).
- `idr-identity`: as today, but the identities are the summary each
  component computes when it is ready, not a round's facts.
- `idr-redirect`: a call whose key has a specialization node calls the
  node's function; it makes no function; a step of idr-optimize's inner
  pipeline.
- `idr-binding-times`: as today, computed per component from its own
  bodies.
- `idr-structure-loops`: 0003 §5 and §6: a frontend `scf.for` whose body
  is free of effects becomes a `linalg.generic`, parallel or a reduction
  for the three folds of 0003 §6; every other loop stays in order.
- `idr-bufferize`: 0003 §8: One-Shot on `idr.func`, whole program, before
  counting, the runtime's allocation and copy, no ownership deallocation,
  a link of a linear thread bufferized in place always (a copy there an
  internal error), ending with the wrapper's one type conversion.
- `idr-stack`: `stack` is an inherent property of `idr.con` it sets.
- `idr-rc`: no options; it runs after the arrays stage; the exclusive
  grades are a key set per function and each copy is made once.
- `idr-demand`: always checks the in-place promise of the types whose
  declaration carries it; the error stays `unsupported (uniqueness)`.
- `idr-lower`: what C16 §1 says the description says, with C16's
  dependent dialects.
- `idr-narrow-lanes`: "after the vectorization schedule" in place of the
  deleted pass's name.
- `idr-target`: also writes, in the module's `dlti.target_system_spec`,
  the facts the schedule library reads (C13).
- `idr-expect`: C12 §2's sentence in place of the property list.
- Every other description: unchanged except a sentence that names a
  deleted pass, which is restated.

**`Pipeline.h`.** Exactly C12 §3's text and includes.

**`Pipeline.cpp`.** One function, `idr::buildPipeline(mlir::OpPassManager
&pm)`, adding C12 §3's rows in order; a comment before each row or group
says why it is there (carry today's reasons for the rows that stay; for
the new rows: deduplication before the solve so label sets are smaller;
defunctionalization before the optimizer so every later pass is
first-order; contification before inlining; dead values once after the
optimizer; the arrays stage on final bodies, `scf` loops still visible to
remove-dead-values, bufferization before counting). Includes add
`mlir/Dialect/Bufferization/Transforms/Passes.h`,
`mlir/Dialect/Transform/Transforms/Passes.h` and `idr/Target/Target.h`
(the entry point). `registerIdrPipeline` as C12 §3.

**`Run.cpp`.**
- The handler (`:248-256`): `verdict.errors` on any error; `verdict.rejected`
  when C04's accessor says the diagnostic is a refusal. The comment at
  `:64-69` restated: a refusal carries its rule.
- Delete the leave-out check (`:77-104`). `runPipeline(module, verdict,
  rootTiming)`: statistics, `applyPassManagerCLOptions`,
  `idr::profile::addInstrumentation`, timing, `createIdrTarget`,
  `buildPipeline(pm)`; no dump instrumentation, no rounds instrumentation;
  its result is the verdict's status or `ok`.
- `toObject` keeps stage 13 (`:149-198`) and replaces `:199-201` with the
  call into C13's entry, under a zone and a timing scope named `codegen`.
- `run(artifacts, rootTiming)`: the handoff registry adds
  `mlir::tensor::TensorDialect` and `mlir::scf::SCFDialect` (and their
  headers); the action handler's comment (`:277-280`) names action logging
  only; delete the dump directory's creation (`:298-303`) and the options
  object (`:294-297`); include `idr/Transforms/Simplify.h` no more.

**`Options.cpp`, `Options.h`.** Delete the four option objects and their
declarations; `-o`'s description becomes "Output: the executable, or with
-c the archive of its objects". `Options.h:48-51`'s comment on statuses:
a refusal, on either side, or any error Idris reports, is 3.

**`Main.cpp`.** Delete `mlir::tracing::DebugCounter::registerCLOptions()`
(`:99`) and `#include "mlir/Debug/Counter.h"` (`:20`); the comment at
`:91-93` says action logging, not debug counters. `frontendOptions`
(`:158-160`) and the usage message (`:162-163`) name `-p`,
`--package-path`, `--prefix` and `--no-prelude` only.

**`Compile.cpp`, `Compile.h`.** The frontend's argument list
(`Compile.cpp:36-46`) loses the shape-breaking hook. `link` passes C13's
objects. `compile` calls `run(artifacts, rootTiming)`. `Compile.h` deletes
`DumpAfterEachPass` (`:61-92`) with the includes only it needed
(`mlir/IR/OperationSupport.h`, `mlir/Pass/PassInstrumentation.h`,
`<optional>`), and declares the new `run`.

**`Dump.cpp`.** Delete the file.

**`tools/idris-mlir-opt.cpp`.** Drop `idr/Transforms/Simplify.h` and the
rounds' instrumentation; the setup function adds only
`idr::profile::addInstrumentation(pm)`; its comment says so. Call C13's
registry function on `registry` before `registerAndParseCLIOptions`.
**`tools/idris-mlir-reduce.cpp`.** Call C13's registry function on
`registry` before the context is made.

**`tools/compile.sh`.** Lines 12-14: the options are "-p PACKAGE, or any
other option of idris-mlir's, -mlir-print-ir-tree-dir=DIR among them";
the files left beside the executable are those C13's `Artifacts` names.

**`Profile.h`, `Profile.cpp`, `Actions.h`, `Actions.cpp`.** `Profile.h:44-48`:
`ThreadTrace` is for a thread a tool spawns and for a task a pass or the
driver runs on a pool itself. `Profile.h:79-80`: an instant ends a stage
of a thing (a compilation). `Profile.cpp:3-6`: the nested and dynamic
pipelines named are a module pass's own and idr-optimize's per-function
one. `Actions.h:3-7`: actions are listed by `-log-actions-to`, narrowed by
`--log-actions-tags`, and bisected by a debug counter in idris-mlir-opt.

**Build lines the coordinator writes** (report them; do not edit a build
list): `IdrPipeline` (`lib/Transforms/CMakeLists.txt:420-461`) drops the
libraries of the deleted passes and links those of `idr-optimize`,
`idr-structure-loops` and `idr-bufferize`, plus
`MLIRBufferizationTransforms` and `MLIRTransformDialectTransforms`;
`IdrDriver` (`foreign/idr/lib/CMakeLists.txt`) drops `Driver/Dump.cpp` and
`IdrSimplify` and links `MLIRTensorDialect` and `MLIRSCFDialect`;
idris-mlir-opt (`foreign/idr/CMakeLists.txt:108-121`) drops `IdrSimplify`;
idris-mlir-opt and idris-mlir-reduce link what C13's registry function
lives in.

**Failure paths.** A pipeline that fails, or an error that is not a
refusal, is `internal error: the pipeline failed` (or `reported an
error`), status 1, as today (`Run.cpp:135-139`). An unknown option is
`llvm::cl`'s usage error, status 2.

## Delete

- The driver options `--without`, `--demand-in-place`, `--dump-dir` and
  `--break-shape`: `Options.cpp:41-57, 64-69`; `Options.h:28-32`; their
  uses `Run.cpp:77-104, 121-126, 140, 294-303`, `Compile.cpp:41-42`,
  `Main.cpp:158-164`.
- `DumpAfterEachPass` (`Compile.h:61-92`) and `lib/Driver/Dump.cpp`.
- `Pipeline.cpp`'s `Sink`, `Build` and `Names` (`:29-89`), `pipelinePassNames`
  (`:182-187`), `PipelineOptions` (`Pipeline.h:44-51`), and the strings
  `"reuse"`, `"sink"` and `"in-place"` (`Pipeline.cpp:119-124`,
  `Run.cpp:83-85`).
- The pass options `idr-rc{reuse,sink}` (`Passes.td:666-671`) and
  `idr-demand{in-place}` (`Passes.td:695-698`).
- The defs `IdrLoopBreakers` (`Passes.td:129-143`, the pass named
  LoopBreakers), `IdrRoundFacts` (`:145-155`, RoundFacts), `IdrSpecialize`
  (`:157-190`), `IdrInline` (`:218-241`), `IdrIsolate` (`:243-263`,
  idr-isolate), `IdrInBounds` (`:479-527`, idr-in-bounds), `IdrSimplify`
  with `max-rounds` and `scc-pipeline` (`:575-620`) and `IdrVectorize`
  (`:702-732`, idr-vectorize); every description sentence naming
  `unsupported (compile-time budget)`, `break_last` or the round; the
  property list of `IdrExpect`'s description (`:775-853`), with
  `breaks-last`, `every-cycle-has-breaker`, `in-bounds` and
  `pure-array-loops` in it.
- The pipeline's calls of idr-isolate, idr-simplify, idr-in-bounds and
  idr-vectorize and the canonicalize group after defunctionalization
  (`Pipeline.cpp:98, 106, 108-109, 133, 143`).
- The rounds' instrumentation where the manager's owners add it
  (`Run.cpp:120`; `tools/idris-mlir-opt.cpp:57-66`) and the includes of
  `idr/Transforms/Simplify.h` (`Run.cpp:15`, `idris-mlir-opt.cpp:12`).
- The driver's decision by the message prefix `"unsupported ("`
  (`Run.cpp:248-254`).
- The debug counter's registration in idris-mlir (`Main.cpp:20, 99`).
- `tools/compile.sh:12-13`'s mention of `--demand-in-place`, `--dump-dir`
  and `--break-shape`.
- `Profile.h:80`'s "a round of idr-simplify".

## NOT TO DO

- Do not write the partition, code generation per bin, the archive,
  `emit` or the schedule library: U07's, in `lib/Target/` and
  `Driver/Artifacts.*`. `Run.cpp` calls them through C13.
- Do not build idr-optimize's inner pipeline or touch `Canonicalize.h`:
  U03's.
- Do not add a `GEN_PASS_DECL` to another lane's header, nor fix one there:
  report it.
- Do not add a pass option, a driver option, an environment variable, a
  second registered pipeline or a variant of `idr-pipeline`; do not keep
  any of `--without`, `--dump-dir`, `--demand-in-place` or `--break-shape`
  hidden.
- Do not register a debug counter in idris-mlir in any form; do not remove
  the one MlirOptMain gives idris-mlir-opt.
- Do not add an instrumentation that writes dumps: upstream's
  `-mlir-print-ir-tree-dir` is the one.
- Do not make a row depend on what the module holds (skip the arrays stage
  without a tensor, for example).
- Do not edit `tests/`, `bench/`, any `CMakeLists.txt`, the frontend
  (`compiler/`), or a tool script other than `tools/compile.sh`.
- Do not add statistics beyond C12 §2, nor a progress remark: the ready
  set's remarks are U03's.

## Tempting partial solutions

- **An empty `PipelineOptions` kept "for later".** Rejected: C12 §3's
  `Pipeline.h` has no such type, and a spec check reads that no option
  selects behaviour. Accept only when `grep -n PipelineOptions` over the
  lane's files finds nothing.
- **`pipelinePassNames()` kept as documentation.** Nothing reads it once
  `--without` goes; accept only when it is defined nowhere.
- **`--dump-dir` kept as an alias of `-mlir-print-ir-tree-dir`.** An option
  that duplicates upstream's; accept only when `idris-mlir --dump-dir=d
  a.mlir -o a` exits 2 as an unknown option.
- **Matching `"unsupported ("` where C04's accessor finds no rule.** Two
  representations of one fact; accept only when no `"unsupported ("`
  literal is left in `lib/Driver`.
- **Registering the debug counter and ignoring it.** Accept only when
  `idris-mlir -mlir-debug-counter=x-skip=1 a.mlir -o a` exits 2.
- **`eliminate-empty-tensors` nested in the structure-loops group.** Without
  a module it analyzes no function boundary and reads siblings from a
  nested pass; accept only the module row of C12 §3.
- **The vectorization entry point as a literal in `Pipeline.cpp`.** The
  name is the schedule library's, held once by C13; accept only a use of
  C13's constant.
- **A thread pool of the driver's own for code generation.** Accept only
  the context's pool, `threadBudget()` sized.
- **Keeping `run(modulePath, objectPath, ...)` and naming the bins'
  objects in `Run.cpp`.** Names of outputs are the `Artifacts`'; accept
  only C12 §5's signature.

## Acceptance

- `python3 proposals/0004-compile-time/check-units.py` on
  `foreign/idr/lib/Driver/{Compile,LinkRuntime,Main,Options,Prepare,ReadRuntime,Run}.cpp`,
  `foreign/idr/lib/Transforms/Pipeline.cpp`,
  `foreign/idr/lib/Support/{Profile,Actions}.cpp` and
  `foreign/idr/tools/{idris-mlir,idris-mlir-opt,idris-mlir-reduce}.cpp`:
  no failure but one caused by a sibling's header or generated file not
  yet written, each listed with its file and contract. `Dump.cpp` is
  reported "not in the build" until the coordinator drops it.
- `Passes.td` through the pinned `mlir-tblgen -gen-pass-decls -name Idr`
  (to a directory under `/tmp`, nothing written in the tree) declares
  `createIdrOptimize`, `createIdrStructureLoops` and `createIdrBufferize`,
  no constructor of a deleted def, no `IdrRcOptions` or
  `IdrDemandOptions`, and `IdrExpectOptions` with `holds` alone.
- Source review: `Option<` and `ListOption<` occur in `Passes.td` once,
  for `holds`; `Options.cpp` defines exactly C12 §4's options; no
  `"unsupported ("` in `lib/Driver`; none of `createSimplifyInstrumentation`,
  `PipelineOptions`, `pipelinePassNames`, `DumpAfterEachPass` or
  `DebugCounter` in the lane's files; `lib/Driver/Dump.cpp` absent; the rows
  of `buildPipeline` equal C12 §3's, in order.
- On the owner's machine (NotRun here, listed in the handoff):
  `idris-mlir-opt --idr-target --idr-pipeline` lowers a program to the
  LLVM dialect; `idris-mlir -mlir-print-ir-tree-dir=d` writes one module
  per pass; an option of ## Delete is an unknown option (status 2); a
  refused program exits 3 and prints its refusal unchanged.

## Stop and return

Stop when items 1 to 6 are done, item 7's adaptations made where C13
requires them, and the checks above run. Return the handoff the common
obligations define. Report without stopping other work: a pass header
that lacks the `GEN_PASS_DECL` C12 names (file, def, owner); C13's
declarations if they differ from what `Run.cpp`, `Compile.cpp` and the
tools call; C04's accessor if absent; `foreign/idr/lib/CMakeLists.txt`,
which holds `IdrDriver`'s sources and is in no lane's writes; and the
build lines above.
