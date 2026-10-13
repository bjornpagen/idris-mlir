# U14 — One typed pass manager; the driver and tools as plain C++

Mandatory findings: F-pass-1 F-pass-5 F-pass-10 F-build-1 F-build-2 F-build-3

## Permitted outcome

1. **One `PassManager` per compilation** (F-pass-5). `idris-mlir` runs
   `idr-target` and the whole pipeline of C1.4 in one `mlir::PassManager`
   that `idr::buildPipeline` fills from constructors. Analyses a pass
   preserves survive to the next pass. Neither the driver nor
   `IDR/Transforms/Pipeline.cpp` calls `parsePassPipeline`. Mandatory.
2. **Nested managers for the function passes** (F-pass-1). The groups of
   C1.4 run under `idr.func` before lowering and `func.func` after it;
   MLIR schedules them over functions in parallel. Mandatory.
3. **`--without` by pass name.** It names any pass of the pipeline, a
   nested one included, or `idr-rc`'s `reuse` and `sink`. The pass is not
   added; its manager stays. A name that is none of these is a usage
   error (status 2) that names it. Mandatory.
4. **`--dump-dir` as a `PassInstrumentation`.** After each top-level pass
   the module is written as `<NN>-<name>.mlir`, numbered from 01 with no
   gap, with locations, name locations as SSA prefixes and aliases on.
   Mandatory.
5. **`idris-mlir-opt` on `MlirOptMain`** with the dialect, every idr pass
   and `--idr-pipeline` registered; `idris-mlir-reduce` on
   `mlirReduceMain` with the same registrations. Mandatory.
6. **The driver, the pipeline and the actions as headers and `.cpp`**
   (F-build-1): `IDR/Driver/*.cpp` with `INC/Driver/*.h`,
   `IDR/Transforms/Pipeline.cpp` with `INC/Transforms/Pipeline.h`,
   `IDR/Support/Actions.cpp` with `INC/Support/Actions.h`. Every `.cppm`
   of the lane is deleted; the three tools include headers. Mandatory.
7. **Built from the presets alone** (F-build-2, F-build-3). No unit of the
   lane carries a compile option, a pragma, a sanitizer attribute, a
   precompiled header or a conditional on a preset. The hardening flags
   live in the `hardened` preset and the sources never name them. Every
   unit is a plain translation unit ccache can key on its text, its flags
   and the headers it includes. Mandatory, as a property of the sources;
   the CMake is the coordinator's.
8. **The verifier on, everywhere in the driver.** The private pass manager
   that set the target with the verifier off goes; `idr-target` runs
   under the one manager, verified like every pass. Mandatory.
9. **The driver's profile layer** (C8.1, C8.2). The one manager gets
   `idr::profile::addInstrumentation(pm)`; each driver phase has one
   `IDR_ZONE_IN`; each compilation ends with `IDR_FRAME("compile")`.
   Mandatory.
10. **Consumer adaptations.** `NamesApart` keeps its mechanism and its
    messages: it compares the names LLVM sees, which after lowering are
    the names `idr-lower` mangled (C2.3). The tools register the dialect
    with `registry.insert<idr::IdrDialect>()`. U06's two actions derive
    from `idr::support::TaggedAction` and call `idr::support::perform`
    from `idr/Support/Actions.h`. Mandatory.

## Owner / exclusive writes

- `IDR/Driver`: every `.cppm` there is deleted; the `.cpp` files of
  "Implement" are new. `IDR/Driver/CMakeLists.txt` is the coordinator's.
- `INC/Driver`: new, one header per unit.
- `IDR/Transforms/Pipeline.cpp`, `INC/Transforms/Pipeline.h`: new.
- `IDR/Support/Actions.cpp`, `INC/Support/Actions.h`: new.
- `IDR/Support/Perform.cppm`, `IDR/Support/TaggedAction.cppm`,
  `IDR/Support/Support.cppm`: deleted.
- `IDR/Dialect/Registration/PipelineSteps.cc`,
  `IDR/Dialect/Registration/RegisterIdrPipeline.cc`: deleted.
- `FI/tools/idris-mlir-opt.cc`, `FI/tools/idris-mlir-reduce.cc`,
  `FI/tools/idris-mlir.cc`: rewritten in place.

**Excluded:**

- `IDR/Dialect/Registration/RegisterIdr.cc` and `INC/Idr.h`: U01's.
- `IDR/Support/Counts.cppm`, `IDR/Support/Statistics.cppm`: U04's.
- `IDR/Support/RaiseAction.cppm`, `IDR/Support/SpecializeCloneAction.cppm`:
  U06's; the two actions move into `IDR/Transforms/Specialize`.
- `INC/Support/Profile.h`, `INC/Support/ProfileSampling.h`,
  `IDR/Support/Profile.cpp`, `IDR/Support/ProfileAlloc.cpp`: U23's.
- `IDR/Target`, `INC/Target/Target.h`, `IDR/Conversion`: U10's.
- `FI/tools/idris-mlir-tblgen.cc`: U20's.
- `INC/Transforms/Passes.td`, every `CMakeLists.txt`, `CMakePresets.json`,
  the top-level `CMakeLists.txt`, `Makefile`, `PINS.md`, `README.md`: the
  coordinator's. The hub text the lane needs is in "Outputs".
- `T/idr/pipeline`, `T/idr/obs`, `T/idr/tail-calls`: U21's.
  `T/compiler`, `T/determinism`, `T/lib`: U22's.
- `runtime/`: nothing changes (C0).

## Read first

- `contracts.md` C0, C1.1, C1.3, C1.4, C1.5, C2.0, C2.3, C5, C8.1, C8.2,
  C11.
- `findings.md` F-pass-1, F-pass-5, F-build-1, F-build-2, F-build-3;
  F-build-4 for what the tools stop linking.
- `IDR/Driver/Run.cppm`, all 255 lines: :50-59 the registrations and the
  contract registry; :60-62 threading; :78-100 the diagnostic handler, the
  verdict and the parse; :101-111 the full registry and `setTarget`;
  :113-128 the action handler; :130 statistics; :132-146 `--without`;
  :147-152 the dump directory; :153-205 one manager per step; :206-252
  LLVM.
- `IDR/Driver/Main.cppm` :22-52 (the options and the three defaults),
  :70-87 (`--prepare-runtime`), :88-113 (a compilation).
- `IDR/Driver/Options.cppm`, all: :43-64 (`without`, `demandInPlace`,
  `logActionsTags`, `dumpDir`), :115-133 (statuses, triple, CPU, clang).
- `IDR/Driver/Dump.cppm` :14-27; `IDR/Driver/SetTarget.cppm` :13-26;
  `IDR/Driver/NamesApart.cppm` :17-21 and :35-52;
  `IDR/Driver/RunOnLargeStack.cppm` :20-43 and :52-59;
  `IDR/Driver/Compile.cppm`; `IDR/Driver/Frontend.cppm`;
  `IDR/Driver/Driver.cppm` (the partition list, which is the unit list).
- The runtime preparation, which changes only in form:
  `IDR/Driver/{Artifacts,Report,Link,LinkRuntime,ReadRuntime,Prepare,PrepareMember,PreparedBitcode,Members,NativeRuns,Retarget,Marks,MarkAnnotated,IsPrepared,ModuleFlagString,SameTarget,BesideObject,Externalize,Emit,WriteOutput}.cppm`.
- `IDR/Driver/CMakeLists.txt` :1-6 and :39-43: what the driver includes
  of the runtime and links.
- `IDR/Dialect/Registration/PipelineSteps.cc` :8-72: the order and the
  comments, which move into `Pipeline.cpp` beside the steps they explain.
  `IDR/Dialect/Registration/RegisterIdrPipeline.cc` :10-19.
- `IDR/Support/Perform.cppm`, `IDR/Support/TaggedAction.cppm`,
  `IDR/Support/Support.cppm`; the two callers
  `IDR/Specialize/Raise.cppm:235` and
  `IDR/Specialize/Specialization.cppm:233`.
- `FI/tools/idris-mlir-opt.cc`, `FI/tools/idris-mlir.cc`,
  `FI/tools/idris-mlir-reduce.cc`.
- `FI/CMakeLists.txt`, read only: :35-40 (the LLVM components the driver
  needs), :274-297 (what the tools link), :316-321 (the driver's compile
  definitions), :349-351 (the Tracy force-load that goes to the profile
  preset), :366-371.
- `INC/Idr.h` :435-441 (`GEN_PASS_DECL`, `GEN_PASS_REGISTRATION`) and
  :589-596 (the declarations this lane replaces).
- `INC/Passes.td` :543-612: `idr-rc`'s `reuse` and `sink`, `idr-demand`'s
  `in-place`, the option names the driver sets.
- `IDR/Target/Pass.cc` :21-37: `idr-target`, which the one manager runs
  first.
- `IDR/Lower/TailCalls.cppm` :1-9, :77, :121, :143: the op
  `idr-tail-calls` reads (see "Escalate if").
- `CMakeLists.txt` :279-310 (the language profile); `CMakePresets.json`;
  `README.md` "Setup" (the sentence on ccache); `PINS.md` `mlir-cxx-api`
  (:61-80), `mlir-recursion` (:312-340),
  `pass-timing-dynamic-pipeline` (:487-510).
- `sources/docs/mlir/docs/PassManagement.md`: "Pass Manager" and
  "OpPassManager" (:344-458), "Dynamic Pass Pipelines" (:459-496), "Pass
  Registration" and "Pass Pipeline Registration" (:633-705), "Textual
  Pass Pipeline Specification" (:706-762), "Pass Instrumentation"
  (:1033-1098), "Pass Timing" (:1105), "IR Printing" (:1255-1422;
  `mlir-use-nameloc-as-prefix` at :1402).
- The pinned MLIR headers, by name, when the toolchain is present:
  `mlir/Pass/PassManager.h` (`OpPassManager::nest`, `addPass`,
  `addInstrumentation`, `enableTiming`, `enableStatistics`,
  `applyPassManagerCLOptions`), `mlir/Pass/PassInstrumentation.h`
  (`runBeforePipeline`, `runAfterPipeline`, `runBeforePass`,
  `runAfterPass`, `runAfterPassFailed`, `PipelineParentInfo`),
  `mlir/Pass/PassRegistry.h` (`PassPipelineRegistration`),
  `mlir/Pass/Pass.h` (`getArgument`, `getOpName`),
  `mlir/Tools/mlir-opt/MlirOptMain.h`,
  `mlir/Tools/mlir-reduce/MlirReduceMain.h`,
  `mlir/IR/OperationSupport.h` (`OpPrintingFlags`), `mlir/IR/Action.h`
  (`tracing::ActionImpl`, `IRUnit`), `mlir/Transforms/Passes.h`,
  `mlir/Conversion/Passes.h`, `mlir/Dialect/Linalg/Passes.h`,
  `mlir/Dialect/MemRef/Transforms/Passes.h`.
- The tests that state the behaviour: `T/idr/pipeline/steps.mlir`,
  `T/idr/pipeline/timing/run`, `T/idr/pipeline/runtime-names.mlir`,
  `T/idr/pipeline/reported-error-fails.mlir`,
  `T/idr/pipeline/inputs.mlir`, `T/idr/obs/stats.mlir`,
  `T/idr/obs/debug-counter.mlir`, `T/idr/tail-calls/mutual.mlir`,
  `T/lib/properties.sh` :40-51, `T/lib/mlir.sh` (`step_module`),
  `T/lib/determinism.sh` (`determinism_threads`), `T/compiler/*/run`.

## Fixed decisions

**The files.** One `.cpp` and one `.h` per unit of today, under the
unit's name (C5), in namespace `idr::driver`; a unit of constants or
templates alone becomes a header alone. `#pragma once`, as `INC/Idr.h:2`
has it. The headers are `INC/Driver/<Name>.h`; the sources
`IDR/Driver/<Name>.cpp`:

- `Options` (.h, .cpp): every `cl::opt` and `cl::list` of
  `Options.cppm:19-113`, declared `extern` in the header and defined in
  the `.cpp` in today's order, since the order of definition is the order
  of `--help`; `ok`, `failure`, `usage`, `rejected`, `targetTriple`,
  `targetCpu`, `pinnedCc` as `inline constexpr` in the header, from the
  same compile definitions as today.
- `Report` (.h only): `Report`, `cannotWrite`.
- `Marks` (.h only): the six `StringLiteral`s.
- `Artifacts`, `WriteOutput`, `Frontend`, `Compile`, `Run`, `Dump`,
  `Link`, `LinkRuntime`, `NamesApart`, `NativeRuns`, `ReadRuntime`,
  `Members`, `PrepareMember`, `PreparedBitcode`, `Prepare`, `Retarget`,
  `MarkAnnotated`, `IsPrepared`, `ModuleFlagString`, `SameTarget`,
  `BesideObject`, `Externalize`, `Emit`, `RunOnLargeStack`, `Main`
  (.h and .cpp each).

That is 26 `.cpp` in `IdrDriver`. `Driver.cppm` (the module interface)
and `SetTarget.cppm` have no counterpart. `Dump` keeps its name and
changes its content.

**`INC/Transforms/Pipeline.h`** is the dialect's `Passes.h` in upstream's
sense: it includes `idr/Transforms/Passes.h.inc` under `namespace idr`
twice, with `GEN_PASS_DECL` and then `GEN_PASS_REGISTRATION`, so that
every `createIdr*` constructor and `idr::registerIdrPasses()` come from
the one `.td`. It then declares:

```cpp
namespace idr {
// What the driver decides about the pipeline: the passes left out by
// argument, with idr-rc's reuse and sink, which are not passes but are
// turned off the same way; and whether idr-demand checks the in-place
// promise.
struct PipelineOptions {
  llvm::StringSet<> without;
  bool demandInPlace = false;
};
// idris-mlir's pipeline, idr-isolate to idr-tail-calls, into `pm`, a
// manager on builtin.module. Never idr-target: the driver runs it first,
// and idris-mlir-opt runs it by name.
void buildPipeline(mlir::OpPassManager &pm, const PipelineOptions &options);
// The argument of every pass buildPipeline adds with no options, nested
// ones included, in order: what --without may name.
std::vector<std::string> pipelinePassNames();
// Registers --idr-pipeline with the pass registry.
void registerIdrPipeline();
}
```

The signature `void idr::buildPipeline(mlir::OpPassManager &, const
PipelineOptions &)` is fixed. No other declaration is added to the
header.

**The pipeline is written once.** `Pipeline.cpp` holds one private
function, `steps(Sink &, const PipelineOptions &)`, whose body is C1.4's
list in order, each pass a constructor call, with the comments of
`PipelineSteps.cc:10-69` beside the steps they explain. `Sink` has three
operations: `top(std::unique_ptr<Pass>)` adds a pass on the module;
`group(StringRef anchor)` starts a nested group; `nested(std::unique_ptr<Pass>)`
adds a pass into the open group. Two sinks read the body: the builder,
which `buildPipeline` runs, and the lister, which `pipelinePassNames`
runs. No list of names exists beside the body.

- The builder: `top` closes any open group and, unless
  `options.without.contains(pass->getArgument())`, calls
  `pm.addPass(std::move(pass))`. `group(anchor)` remembers the anchor
  and opens nothing yet. `nested` skips a pass named in `without`;
  otherwise it opens the group on first use with `pm.nest(anchor)` and
  adds the pass there. So a group whose passes are all left out is not
  created, and a group with one pass left out keeps its manager. The
  anchors are `idr::FuncOp::getOperationName()` before lowering and
  `mlir::func::FuncOp::getOperationName()` after it, which is what
  `pm.nest<OpT>()` passes to `nest(StringRef)`.
- The lister: `top` and `nested` push `pass->getArgument().str()`;
  `group` does nothing. It runs the body with `PipelineOptions{}`.
- `idr-rc` is built as
  `createIdrRc(IdrRcOptions{.reuse = !without.contains("reuse"), .sink = !without.contains("sink")})`;
  `idr-demand` as `createIdrDemand(IdrDemandOptions{.inPlace = options.demandInPlace})`.
  The generated option structs and their field names come from the `.td`
  (`INC/Passes.td:576-577`, :606 today).
- `idr-tail-calls` is the last group. Its anchor is the one the
  constructed pass declares, `*pass->getOpName()`, not a type the lane
  writes, so that the nest and the pass agree whatever `Passes.td` says
  (see "Escalate if" for what it should say).
- Upstream passes are built with the constructors their headers declare
  for the pass names of C1.4: `createCanonicalizerPass()`,
  `createCSEPass()` (`mlir/Transforms/Passes.h`);
  `createConvertLinalgToLoopsPass()` (`mlir/Dialect/Linalg/Passes.h`);
  `memref::createExpandStridedMetadataPass()`
  (`mlir/Dialect/MemRef/Transforms/Passes.h`); and from
  `mlir/Conversion/Passes.h` the constructors for `convert-vector-to-scf`,
  `lower-affine`, `convert-scf-to-cf`, `convert-vector-to-llvm`,
  `convert-to-llvm` and `reconcile-unrealized-casts`
  (`createConvertVectorToSCFPass`, `createLowerAffinePass`,
  `createSCFToControlFlowPass`, `createConvertVectorToLLVMPass`,
  `createConvertToLLVMPass`, `createReconcileUnrealizedCastsPass`). Where
  the pinned header spells one differently, the header is right; no
  option is set on any of them, as today's text set none.

**`--without`.** The driver accepts a name when it is `reuse` or `sink`,
or when it starts with `idr-`, is not `idr-lower` and is an element of
`pipelinePassNames()` (today's rule, `Run.cppm:136-139`, with the step
list replaced by the real pipeline). Otherwise
`Report() << "--without names " << name << ", which is neither a pass of the pipeline nor reuse or sink"`
and `usage`. The accepted names go into `PipelineOptions::without`.

**`idr-target` is the first pass of the driver's manager**, added by
`Run.cpp` with `createIdrTarget()` before `buildPipeline`. It is not in
`--idr-pipeline`: `T/idr/pipeline/steps.mlir:5` and
`T/lib/determinism.sh` run `--idr-target --idr-pipeline`, and keep doing
so. `setTarget`, its private manager and its `enableVerifier(false)`
(`SetTarget.cppm:21`) go; the verify after `idr-target` is MLIR's.

**The one manager, in this order.** `mlir::PassManager pm(&context)`;
`pm.enableStatistics(mlir::PassDisplayMode::List)` when
`llvm::AreStatisticsEnabled()`; `mlir::applyPassManagerCLOptions(pm)`,
`usage` on failure; `pm.addInstrumentation(DumpAfterEachPass)` when
`--dump-dir` is given; `idr::profile::addInstrumentation(pm)`, always;
`pm.enableTiming(rootTiming)` last. Instrumentations unwind in reverse
order of addition, so adding the dump before the timer keeps the print
of a dump out of the pass's time, as `Run.cppm:201-202` kept it. Then
`pm.addPass(createIdrTarget())`, `idr::buildPipeline(pm, options)`,
`pm.run(*module)`. A failed run or a reported error is handled as
`Run.cppm:194-199` handles a step: `status(verdict)`, and
`Report() << "internal error: the pipeline " << (ran ? "reported an error" : "failed")`
when nothing rejected the program. A dump the instrumentation could not
write fails the compilation with `failure` after the run.

**`DumpAfterEachPass`** (`INC/Driver/Dump.h`, `IDR/Driver/Dump.cpp`) is
a `mlir::PassInstrumentation`:

- It counts nesting: `runBeforePipeline` adds one to `depth`,
  `runAfterPipeline` takes one. The instrumentor serializes every hook,
  so `depth` is a plain `unsigned`. A pass at depth zero is top-level; the
  round's passes (inside `idr-simplify`'s `runPipeline`), `idr-rc-place`,
  `idr-target`'s two derivations and every function pass are deeper and
  never dump.
- `runBeforePass` at depth zero remembers the pass and clears the group
  name; at depth one, under a remembered pass whose `getArgument()` is
  empty (a nested manager), it records the first argument it sees. This
  is today's rule for a step of several passes: the dump is named by the
  first pass (`Run.cppm:23-26`; `T/lib/mlir.sh` finds a step's dump by
  that name and takes the first of two).
- `runAfterPass` at depth zero writes `<NN>-<name>.mlir` into the
  directory: `NN` is the number of dumps written so far plus one, two
  digits (`llvm::formatv("{0:02}-{1}.mlir", ...)` as `Dump.cppm:18`);
  `name` is the pass's argument, else the recorded first nested
  argument; with neither (a nested group that ran no pass) nothing is
  written. `runAfterPassFailed` writes nothing.
- The printing flags are
  `mlir::OpPrintingFlags().enableDebugInfo().printNameLocAsPrefix()`;
  aliases are on by default. A file that cannot be opened is reported
  with `cannotWrite(path, error)` once and sets `failed()`.
- The directory is created before the run, as `Run.cppm:147-152` does.

**Timing.** `pm.enableTiming(rootTiming)`: each top-level pass is a row
directly under the root, named as MLIR's pass timing names it, beside
`parse`, `LLVM` (with `translate`, `link runtime`, `optimize`,
`codegen`) and `link`. The per-step scopes `step N: ...` and `stepName`
go; their reason (`Run.cppm:180-184`) was a manager per step. Timers of
dynamic pipelines nest under their pass by the carried patch
(`PINS.md` `pass-timing-dynamic-pipeline`); nothing here depends on it.

**Registration.** `Run.cpp` calls `mlir::registerAllPasses()` and
`idr::registerIdrPasses()` where `Run.cppm:51-52` calls them today: the
pass-name options `applyPassManagerCLOptions` reads need the registry.
`idr::registerIdrPipeline()` registers the pipeline only:
`PassPipelineRegistration<>("idr-pipeline", "idris-mlir's pipeline, the idr dialect to the LLVM dialect", [](mlir::OpPassManager &pm) { buildPipeline(pm, PipelineOptions{}); })`.
The two tools call `mlir::registerAllPasses()`, `idr::registerIdrPasses()`
and `idr::registerIdrPipeline()`.

**The tools.** `idris-mlir.cc` includes `idr/Driver/Main.h` and calls
`idr::driver::main`. `idris-mlir-opt.cc` includes `idr/IR/IdrDialect.h`,
`idr/Transforms/Pipeline.h`, `idris_rt.h`, the three `mlir/InitAll*.h`
and `MlirOptMain.h`; the registry is `registerAllDialects`,
`registerAllExtensions`, then `registry.insert<idr::IdrDialect>()`; the
run stays on the reserved stack with today's sizes and messages
(`idris-mlir-opt.cc:19-57`). `idris-mlir-reduce.cc` registers the same
and calls `mlirReduceMain`; it has no reserved stack, as today.

**`RunOnLargeStack` keeps everything but its module wrapper:**
`idris_rt_run_on_stack`, the reservation `size_t{1} << 40` with the guard
`size_t{1} << 20`, `compilationExhausted` (`write` and `_exit` only, the
same message), the `Report()` when no stack could be reserved, and the
PIN(mlir-recursion) comment.

**`NamesApart`.** The check stays where it is, on the LLVM module after
translation (`Run.cppm:240-241`, `LinkRuntime.cppm:27`), with
`linkerName` through `llvm::Mangler` (`NamesApart.cppm:17-21`). Every
program symbol there is the name `idr-lower` mangled at the boundary, so
the comparison is of mangled names (C2.3) with no mangler of the
driver's own. Its two messages are unchanged
(`T/idr/pipeline/runtime-names.mlir:3`, :7).

**`INC/Support/Actions.h`:**

```cpp
namespace idr::support {
// An action of MLIR's action framework whose only distinction is its tag.
// The TypeID is owned here, one per action, a constant identity.
template <typename Derived>
struct TaggedAction : mlir::tracing::ActionImpl<Derived> {
  using mlir::tracing::ActionImpl<Derived>::ActionImpl;
  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }
  void print(llvm::raw_ostream &os) const override { printTag(os, Derived::tag); }
};
// `tag` in backquotes: how every tagged action prints (Actions.cpp).
void printTag(llvm::raw_ostream &os, llvm::StringRef tag);
// Runs `transform` as an action A on `op` unless the context's handler
// skips it; whether it ran. Thin: every user instantiates it.
template <typename A>
bool perform(mlir::Operation *op, llvm::function_ref<void()> transform);
}
```

`perform` is `Perform.cppm:15-26` verbatim. `Actions.cpp` defines
`printTag`, which is `TaggedAction.cppm:23` moved out of the template.
The comments of `Perform.cppm:1-5` and `TaggedAction.cppm:1-4` move with
them.

**Includes.** `Run.cpp` and `Pipeline.cpp` include `idr/IR/IdrDialect.h`
first among ours (C1.1); the tools likewise. The other driver units name
no symbol of the dialect and include LLVM's and MLIR's headers by name
(see "Escalate if").

**Profile zones.** `Compile.cpp` includes `idr/Support/Profile.h`,
wraps `frontend(...)` in `IDR_ZONE_IN("frontend", Driver)` and
`link(...)` in `IDR_ZONE_IN("link", Link)`, and marks
`IDR_FRAME("compile")` on every return of `compile()`
(`llvm::make_scope_exit` at its top). `Run.cpp` wraps the parse in
`IDR_ZONE_IN("parse", Parse)` and the four LLVM stages in
`IDR_ZONE_IN("translate", LLVM)`, `("link runtime", LLVM)`,
`("optimize", LLVM)`, `("codegen", LLVM)`, each where its `TimingScope`
is. The passes get their zones from `addInstrumentation`; the driver
adds none for them. No unit of the lane tests `TRACY_ENABLE`.

**Threading** stays on, as `Run.cppm:60-62`; `--mlir-disable-threading`
is MLIR's own option.

## Inputs

- C1.3's passes through the generated constructors of
  `INC/Transforms/Passes.h.inc`: `createIdrTarget`, `createIdrIsolate`,
  `createIdrContify`, `createIdrSimplify`, `createIdrDefunctionalize`,
  `createIdrStack`, `createIdrAccumulate`, `createIdrRc(IdrRcOptions)`,
  `createIdrDemand(IdrDemandOptions)`, `createIdrTrmc`,
  `createIdrTailLoops`, `createIdrNarrow`, `createIdrInBounds`,
  `createIdrLower`, `createIdrEntry`, `createIdrVectorize`,
  `createIdrNarrowLanes`, `createIdrReturnedArguments`,
  `createIdrTailCalls`; and `registerIdrPasses()`, which registers every
  pass of the `.td`, `idr-expect` and `idr-binding-times` included.
- `idr::IdrDialect` and `idr::FuncOp` from `idr/IR/IdrDialect.h` (C1.1,
  C1.2).
- `idr::target::machine` and `idr::target::optimize` from
  `idr/Target/Target.h` (U10), as `Run.cppm:220`, :250 and
  `Prepare.cppm:50-51`, :83 use them.
- `idr/Support/Profile.h` (C8.1, U23): `IDR_ZONE_IN`, `IDR_FRAME`,
  `idr::profile::addInstrumentation(mlir::PassManager &)`.
- The upstream constructors named under "The pipeline is written once".
- `idris_rt.h`: `idris_rt_run_on_stack`. `cpu_features.h`:
  `IDRIS_RT_CPU_FEATURES`. The generated `idr/TargetEntry.h`:
  `IDRIS_MLIR_LINK_FLAGS`. The compile definitions
  `IDRIS_MLIR_TARGET_TRIPLE`, `IDRIS_MLIR_TARGET_CPU`,
  `IDRIS_MLIR_RUNTIME`, `IDRIS_MLIR_RUNTIME_BITCODE_SECTION`,
  `IDRIS_MLIR_PINNED_CC`, `IDRIS_MLIR_IDRIS_PREFIX`.
- The presets of C1.5, consumed as they are.

## Outputs

- `idr::PipelineOptions`, `idr::buildPipeline`, `idr::pipelinePassNames`,
  `idr::registerIdrPipeline`, and `idr::registerIdrPasses` with every
  `createIdr*` through `idr/Transforms/Pipeline.h`. Consumers: `Run.cpp`,
  `idris-mlir-opt.cc`, `idris-mlir-reduce.cc`.
- `idr::support::TaggedAction<Derived>`, `idr::support::perform<A>`,
  `idr::support::printTag` through `idr/Support/Actions.h`. Consumer:
  U06's `RaiseAction` and `SpecializeCloneAction`.
- `idr::driver::DumpAfterEachPass` through `idr/Driver/Dump.h`. Consumer:
  `Run.cpp`.
- The `.cpp` lists for the coordinator's `CMakeLists.txt`:
  - `IdrDriver`: `Artifacts.cpp BesideObject.cpp Compile.cpp Dump.cpp
    Emit.cpp Externalize.cpp Frontend.cpp IsPrepared.cpp Link.cpp
    LinkRuntime.cpp Main.cpp MarkAnnotated.cpp Members.cpp
    ModuleFlagString.cpp NamesApart.cpp NativeRuns.cpp Options.cpp
    Prepare.cpp PrepareMember.cpp PreparedBitcode.cpp ReadRuntime.cpp
    Retarget.cpp Run.cpp RunOnLargeStack.cpp SameTarget.cpp
    WriteOutput.cpp` (26);
  - `IdrPipeline`: `Pipeline.cpp`;
  - `IdrSupport`: `Actions.cpp` (U23 adds its own).
- Hub text the lane needs, stated here and in the handoff:
  - `IdrDriver` gets the four compile definitions of
    `FI/CMakeLists.txt:316-321` as `PRIVATE`; `idr/TargetEntry.h`,
    `idris_rt.h` and `cpu_features.h` on its include path, as
    `IDR/Driver/CMakeLists.txt:1-6` and :39-43 give them; it links
    `IdrPipeline IdrTarget IdrIR idris_rt`, `MLIRParser MLIRPass MLIRDebug
    MLIRTargetLLVMIRExport MLIRBuiltinToLLVMIRTranslation
    MLIRLLVMToLLVMIRTranslation MLIRRegisterAllDialects
    MLIRRegisterAllExtensions MLIRRegisterAllPasses MLIRFuncDialect
    MLIRArithDialect MLIRMathDialect MLIRUBDialect MLIRMemRefDialect
    MLIRLLVMDialect` and `${IDR_LLVM_CODEGEN_LIBS}`
    (`FI/CMakeLists.txt:40`).
  - `IdrPipeline` links every library of C1.1 that defines a pass the
    `.td` declares (`IdrSimplify IdrInline IdrSpecialize
    IdrDefunctionalize IdrOwnership IdrTail IdrNarrow IdrInBounds
    IdrSmallPasses IdrVectorize IdrExpect IdrEffects IdrConversion
    IdrTarget IdrIR`) and `MLIRPass MLIRTransforms MLIRLinalgTransforms
    MLIRVectorToSCF MLIRMemRefTransforms MLIRAffineToStandard
    MLIRSCFToControlFlow MLIRVectorToLLVMPass MLIRConvertToLLVMPass
    MLIRReconcileUnrealizedCasts`.
  - `idris-mlir` links `IdrDriver`; `idris-mlir-opt` links `IdrPipeline
    IdrIR idris_rt MLIROptLib MLIRRegisterAllDialects
    MLIRRegisterAllExtensions MLIRRegisterAllPasses`; `idris-mlir-reduce`
    links `IdrPipeline IdrIR MLIRReduceLib` and the three `RegisterAll`
    libraries. All three take `idris_mlir_language_profile`. The Tracy
    client and its force-load (`FI/CMakeLists.txt:349-351`) are the
    profile preset's alone (C1.5).

## Implement

**`IDR/Transforms/Pipeline.cpp`** (one unit, under 400 lines): includes
`idr/IR/IdrDialect.h`, `idr/Transforms/Pipeline.h`, then
`mlir/Dialect/Func/IR/FuncOps.h`, `mlir/Pass/PassManager.h`,
`mlir/Pass/PassRegistry.h`, `mlir/Transforms/Passes.h`,
`mlir/Conversion/Passes.h`, `mlir/Dialect/Linalg/Passes.h`,
`mlir/Dialect/MemRef/Transforms/Passes.h`. In an anonymous namespace:
`Sink`, `Build` (holds `OpPassManager &pm`, `const PipelineOptions &`,
the pending anchor and the open group), `Names` (holds the vector), and
`steps`. Then `buildPipeline` (a `Build` over `steps`),
`pipelinePassNames` (a `Names` over `steps` with `PipelineOptions{}`) and
`registerIdrPipeline`. Nothing in the unit is a string that names a pass.

**`IDR/Driver/Run.cpp`** keeps `Run.cppm`'s shape and order:
registrations (:51-52, with `registerIdrPasses` in place of the pipeline
registration); the contract registry (:55-58, with
`contract.insert<idr::IdrDialect>()`); the context; the targets; the
prepare branch; the diagnostic handler and the verdict; the parse under
its timer and zone; the full registry; the action handler; statistics;
`--without` through `pipelinePassNames`; the dump directory; the one
manager as "Fixed decisions" orders it; `idr-target` and the pipeline;
the run; the dump failure; LLVM as :206-252, with the zones. `setTarget`
and the loop over steps are gone.

**`IDR/Driver/Dump.cpp`** defines `DumpAfterEachPass` as fixed above;
nothing else. **`IDR/Driver/Compile.cpp`** adds the two zones and the
frame mark. **`IDR/Driver/Main.cpp`** is `Main.cppm` with includes.
**`IDR/Driver/Options.cpp`** defines the options in today's order. Every
other driver unit is its `.cppm` with the module lines replaced by
includes, its `export` keywords removed, and its header declaring what
other units call.

**`IDR/Support/Actions.cpp`**: `printTag`.

**The tools** as fixed above.

**Failure paths**, unchanged in meaning: a usage error before anything is
armed leaves every file (`Main.cppm:101-110`); a rejection
(`unsupported (...)`) is status 3, an internal error 1, a usage error 2;
an error reported by any pass fails the compilation even when the pass
goes on (`Run.cppm:28-33`); a dump that cannot be written is `failure`;
`--without` of an unknown name is `usage` with the name.

## Delete

- `IDR/Driver/Driver.cppm`, `Artifacts.cppm`, `BesideObject.cppm`,
  `Compile.cppm`, `Dump.cppm`, `Emit.cppm`, `Externalize.cppm`,
  `Frontend.cppm`, `IsPrepared.cppm`, `Link.cppm`, `LinkRuntime.cppm`,
  `Main.cppm`, `MarkAnnotated.cppm`, `Marks.cppm`, `Members.cppm`,
  `ModuleFlagString.cppm`, `NamesApart.cppm`, `NativeRuns.cppm`,
  `Options.cppm`, `Prepare.cppm`, `PrepareMember.cppm`,
  `PreparedBitcode.cppm`, `ReadRuntime.cppm`, `Report.cppm`,
  `Retarget.cppm`, `Run.cppm`, `RunOnLargeStack.cppm`, `SameTarget.cppm`,
  `SetTarget.cppm`, `WriteOutput.cppm`: every `export module idr.driver`
  partition, its `import idr.mlir`, `import idr.dialect` and
  `import idr.target` lines, and `import idr.driver;` in
  `FI/tools/idris-mlir.cc`.
- `setTarget` and its private pass manager with `enableVerifier(false)`.
- `IDR/Dialect/Registration/PipelineSteps.cc` with `idr::pipelineSteps()`,
  the step strings, and `IDR/Dialect/Registration/RegisterIdrPipeline.cc`
  with its `parsePassPipeline` of each step. The declarations
  `registerIdrPipeline` and `pipelineSteps` at `INC/Idr.h:592-595` are
  replaced by `Pipeline.h`'s; the file is U01's to delete.
- In the driver: `stepName`, the loop over the steps, the manager per
  step, the `step N: ...` timing scopes, the `--without` check against
  the step list, the `idr-rc{...}` and `idr-demand{...}` option texts.
- `IDR/Support/Perform.cppm`, `IDR/Support/TaggedAction.cppm`,
  `IDR/Support/Support.cppm` (`export module idr.support`, which also
  re-exported U04's and U06's partitions).
- The calls of `idr::registerIdr(DialectRegistry &)` in `Run.cppm:58`,
  `idris-mlir-opt.cc:34`, `idris-mlir-reduce.cc:17`; the function itself
  is U01's (`RegisterIdr.cc`).

## NOT TO DO

- Do not build a manager from text anywhere in the lane: no
  `parsePassPipeline`, no array of step strings, no `--pipeline=<text>`
  option. `idris-mlir-opt`'s own `--pass-pipeline` is MlirOptMain's.
- Do not put `idr-target` into `--idr-pipeline`, and do not give
  `--idr-pipeline` options.
- Do not add a `--without` of a round member, of `canonicalize`, of
  `cse`, of an anchor, or of `idr-lower`; the accepted set is today's.
- Do not write `INC/Transforms/Passes.td`, any `CMakeLists.txt`,
  `CMakePresets.json`, the top-level `CMakeLists.txt`, `Makefile`,
  `PINS.md`, `README.md`, `AGENTS.md`: the coordinator's. Report hub text.
- Do not write `INC/Support/Profile.h` or `addInstrumentation` (U23); do
  not add a zone inside a pass; do not test `TRACY_ENABLE` in the driver.
- Do not change the round, its remarks or its statistics (U04); do not
  touch `IDR/Target` or the lowering (U10); do not implement or call a
  mangler in the driver (U10 writes `idr::conversion::mangle` for
  `idr-lower`).
- Do not change a message a test reads: `runtime-names.mlir:3`, :7;
  `inputs.mlir:12-13`; `reported-error-fails.mlir:10`;
  `frontend-beside/run` (the frontend's real path).
- Do not add a bytecode writer or reader. `inputKind` keeps accepting
  `.mlirbc` (`Artifacts.cppm:17-20`; `T/idr/pipeline/inputs.mlir:5-7`
  compiles one); C5's sentence is about the handoff.
- Do not fold the small driver units into one or rename them (C5); do
  not add an umbrella header.
- Do not call `enableVerifier`, `enableIRPrinting` or
  `enableCrashReproducerGeneration` yourself; `-mlir-print-ir-*` and the
  reproducer options arrive through `applyPassManagerCLOptions`.
- Do not change a number: the stack reservation and guard, the three
  defaults of `Main.cppm:46-47`, the two-digit dump index.
- Do not write a test. U21 adapts `T/idr/pipeline/steps.mlir`,
  `timing/run`, `T/idr/obs/*`, `T/idr/tail-calls/mutual.mlir`; U22 keeps
  `T/compiler/*`, `T/determinism/*`, `T/lib/*`. Describe in the handoff
  what each needs (the row names of the timing report; the dump names).
- Do not fix the anchor of `idr-tail-calls` in the `.td` (see "Escalate
  if"); do not move the pass.
- Do not touch `runtime/`, `third_party/`, `upstream/`.

## Stop and return

You are done when: the 26 driver `.cpp` and their headers,
`Pipeline.cpp` with `Pipeline.h`, `Actions.cpp` with `Actions.h` exist as
fixed above; the three tools include headers and nothing else of ours;
every `.cppm` of the lane and the two registration units are deleted;
`Run.cpp` holds one `PassManager`; no string in the lane names a pass
but the diagnostics. Return the changed paths mapped to the outcomes,
the three `.cpp` lists, the hub text of "Outputs", the contract names
supplied, `Verification: NotRun (swarm policy)`, and the seams.

Seams to report without stopping: the anchor `Passes.td` gives
`idr-tail-calls`; the spelling of the name-location printing flag at
the pin; the exact upstream constructor names at the pin where they
differ from those named here; the names the `timing/run` fixture and the
dump-reading fixtures need from U21.

## Acceptance

- `T/idr/pipeline/steps.mlir` (U21): `--dump-dir` leaves files
  `NN-<name>.mlir` numbered 01, 02, ... with no gap, at least two;
  `idris-mlir-opt --idr-target --idr-pipeline` on the input, reprinted,
  equals the last dump reprinted, byte for byte;
  `--without=idr-returned-arguments,idr-stack,sink,reuse` compiles, with
  no `idr-stack` dump and an `idr-rc` dump; `--without=idr-lower` and
  `--without=idr-sinking` exit 2.
- `T/idr/pipeline/timing/run` (U21 rewrites the row names): with
  `--mlir-timing`, `parse` is one row before the passes; each top-level
  pass that ran is a row of its own at the top, in order, with the
  nested managers' passes as rows inside theirs; nothing else at the top
  but `LLVM`, `Rest` and `Total`; `Rest` is not negative. The pipeline's
  rows are the passes' names as MLIR gives them, not `step N`.
- `T/idr/e2e/statics.mlir`: the report names `IdrLower` and `LLVM`.
- `T/idr/pipeline/runtime-names.mlir`: a program that defines
  `idris_rt_live_cells` or `write` is refused before the link, exit 1,
  with today's two messages; under its own name it compiles and exits 7.
- `T/idr/pipeline/reported-error-fails.mlir`: an action log that cannot
  be opened is exit 2 and no object; without it the module compiles.
- `T/idr/pipeline/inputs.mlir`, `link.mlir`, `layout.mlir`,
  `endless-loop.mlir`, `nested-constant.mlir` (the reserved stack of
  `idris-mlir-opt` parses an attribute nested 100,000 deep): unchanged.
- `T/idr/obs/stats.mlir`: `--stats` prints `Pass statistics report` with
  `IdrSimplify` and `IdrDefunctionalize`; without it, nothing.
  `T/idr/obs/debug-counter.mlir`: a dump `*-idr-simplify.mlir` exists.
  `T/idr/obs/round-trace.mlir`, `budget.mlir`, `round-failure.mlir`:
  `idris-mlir-opt --idr-simplify` with its remarks and statuses, as U04
  states them.
- `T/idr/tail-calls/mutual.mlir`: with `--without=idr-tail-calls` the
  last dump fails `constant-stack`; without the option it holds. The
  last dump of the full run is named after `idr-tail-calls`, the first
  pass of its group.
- `T/idr/vectorize/rows-*.mlir`: `idris-mlir-opt --idr-target
  --idr-pipeline` reaches the LLVM dialect.
- `T/idr/e2e/reduce.mlir`, `T/idr/verify/reduce-regions.mlir`:
  `idris-mlir-reduce` with the idr dialect and its passes.
- `T/compiler/*` (U22), the nine: `artifacts` (outputs made and kept on
  success, removed on a later failure with exit 3), `dialect-syntax`
  (`idris-mlir-opt` parses the samples and reprints them to the same
  bytes), `elaboration-error` (exit 3, the pipeline did not run, no
  artifact), `frontend-beside` (the frontend by the real path beside the
  tool; a module needs none), `frontend-command-line`,
  `frontend-named-file`, `main-visible`, `module-location` (the module
  at main's line), `no-environment`.
- `T/determinism/threads-rbtree`, `threads-shapes` (U22): `idris-mlir-opt
  --idr-target --idr-pipeline` under `--mlir-disable-threading`, under
  the pool and under the pool again gives the same bytes with
  `--mlir-print-debuginfo` and the same `--mlir-pass-statistics` list.
  `T/determinism/{hello,leet-rotate,rbtree,shapes}`: two compilations
  give identical `.core`, `.mlir`, object, executable and every dump.
- Every e2e `dumps: parse and verify` line (`T/lib/properties.sh:40-51`):
  each `NN-*.mlir` parses and verifies under
  `idris-mlir-opt --mlir-disable-threading`; `simplify: idempotent` reads
  `*-idr-simplify.mlir`; `quantities: kept` reads every dump before
  `*-idr-lower.mlir`. Both names are module passes and dump under their
  own argument.
- Source conditions compilation does not establish: no `.cppm` under
  `IDR/Driver` or in the lane's `Support` files; no `parsePassPipeline`
  under `IDR/Driver`, `IDR/Transforms/Pipeline.cpp` or `FI/tools`; no
  `enableVerifier` anywhere in the lane; every `.cpp` and `.h` at 400
  lines or fewer; no `thread_local`, `std::atomic` or mutable static but
  the command-line objects (see "Escalate if").
- **Tempting partials, rejected:** a loop that builds one `PassManager`
  per step from constructors (F-pass-5: no analysis would survive a
  step); a second list of step names kept for `--without` (the thing
  being deleted); naming a nested group's dump after the adaptor's own
  `getName()` (`Pipeline Collection ...`; `T/lib/mlir.sh` finds a step's
  dump by its first pass); keeping `setTarget`'s manager because it is
  cheap (C0 forbids the verifier off).

## Escalate if

- **The anchor of `idr-tail-calls`.** C1.3 and C1.4 anchor it on
  `func.func`, after `convert-to-llvm`. At 25890d32 the pass reads
  `llvm.func` and `llvm.call` (`IDR/Lower/TailCalls.cppm:77`, :121,
  :143; `TailCalls.cppm:8`: "runs last, on the LLVM dialect") and needs
  the module's cycles of calls. Under `func.func` it would run on
  nothing. The lane nests it on the anchor its constructor declares and
  reports; the coordinator fixes C1.3's anchor (and U10's pass) or rules
  otherwise.
- **`NamesApart` and a mangler.** If the coordinator reads C2.3 as the
  driver calling `idr::conversion::mangle`, report: the check runs on the
  LLVM module after translation (`Run.cppm:240-241`,
  `LinkRuntime.cppm:27`, `NamesApart.cppm:35`), where every program
  symbol is already the mangled name, and the readable symbol is gone.
  Moving the check before lowering, onto `idr.func` symbols mangled
  through `mangle` and reported at the function's location, is a
  contract edit, not the lane's.
- **The printing flag's name.** The lane names
  `OpPrintingFlags::printNameLocAsPrefix` for `mlir-use-nameloc-as-prefix`
  (`PassManagement.md:1402`). If the pinned `mlir/IR/OperationSupport.h`
  spells it otherwise, use its spelling and report it.
- **The command-line objects.** C1.1 and C2.0 forbid a mutable static
  under `FI`. LLVM's command line is a registry of global `cl::opt`
  objects (`Options.cppm:19-113`; `mlir-opt`'s are the same), written
  once by `ParseCommandLineOptions` before anything runs; and
  `TaggedAction::resolveTypeID` holds a function-local
  `SelfOwningTypeID`, a constant identity (`TaggedAction.cppm:19`). The
  lane keeps both and reports them, so that the coordinator's
  `spec/mlir-layout` rule (C9.3) names the exception.
- **"Every `.cpp` includes `idr/IR/IdrDialect.h` first."** Twenty-five
  of the driver's 26 units name no symbol of the dialect; they read LLVM IR,
  archives and the C ABI. With no precompiled header (C1.5), that
  include costs each of them most of a unit's parse
  (`FI/CMakeLists.txt:87-90`). The lane includes it where the dialect is
  named (`Run.cpp`, `Pipeline.cpp`, the tools) and reports the reading.
- **`reuse` and `sink` move.** If the coordinator's `Passes.td` moves
  `idr-rc`'s `reuse` and `sink` to `idr-rc-place` (U08 nests it), the
  driver cannot set them from the top level: report, with the option
  names found; `--without=reuse,sink` then needs an option on `idr-rc`
  that it forwards.
- **The pipeline hooks.** The dump's depth rule relies on
  `runBeforePipeline` and `runAfterPipeline` being called for every
  nested manager and every `Pass::runPipeline`, with the top-level
  manager outside them (`PassManagement.md:1033-1098`). If the pinned
  `OpToOpPassAdaptor::runPipeline` does otherwise, the round's module
  passes would dump; report the code found before choosing another
  criterion.
- **An upstream pass of C1.4 refuses the module anchor.** Each of
  `convert-linalg-to-loops`, `convert-vector-to-scf`,
  `expand-strided-metadata`, `lower-affine`, `convert-scf-to-cf`,
  `convert-vector-to-llvm`, `convert-to-llvm` and
  `reconcile-unrealized-casts` is op-agnostic or module-anchored at the
  pin, as today's text ran them at the top level. If one declares a
  function anchor, report it; nesting it is C1.4's change to make.
- **A dump-reading fixture needs a name the rule does not give.** The
  first-pass rule names the groups `canonicalize`, `idr-accumulate`,
  `idr-trmc`, `idr-vectorize`, `canonicalize`, `idr-tail-calls`. If a
  fixture of U21 or U22 reads a dump by a pass name that is now second in
  its group (`idr-tail-loops`, `idr-narrow-lanes`,
  `idr-returned-arguments`, `cse`), report the fixture; the rule is the
  contract's and the fixture adapts.
