# LLVM trunk: what 7208ba24 brings to the pins

The LLVM pin moves from `llvmorg-23.1.2` (85ac5602) to llvm main at
7208ba24 (24.0.0git), as `proposals/0003-llvm-trunk.md` decides. This note
is the survey its fourth step asks for. Every PINS.md entry, and every
workaround in `foreign/idr/`, `runtime/`, `CMakeLists.txt` and `tools/`, was
checked against what MLIR and LLVM changed between the two commits. Every
trunk mechanism that one of them could use gets a verdict: adopt now, later
(and on what condition), or not at all.

The survey reads the two trees, through `git diff 85ac5602 7208ba24` in
`.toolchain/llvm-project`. The history between the commits is not fetched,
so changes are named by file and line, not by commit. The survey was
written before any toolchain was built from 7208ba24. Since then
`.toolchain/llvm-macos` has been built at the pin on arm64 macOS
(2026-10-09, with `upstream/` 02-07, 09 and 15 and
`LLVM_FORCE_ENABLE_STATS`), and each passage that the build or a run on
it settled says what it showed, and where. `.toolchain/llvm-musl`
(x86_64 Linux) is not rebuilt at the pin, so nothing here was run there.
llvm-project paths and line numbers are at 7208ba24 unless a line says
23.1.2. Claims are marked: read, measured, decision, conjecture.

## The three entries whose retire condition names a toolchain bump

- **`llvm-cxx17-headers`: retired.** LLVM still sets
  `LLVM_REQUIRED_CXX_STANDARD 17` (read: `llvm/CMakeLists.txt:93`), so its
  headers are still the ones the entry describes, and the entry's rule was
  to delete it if the stage-2 clang of 7208ba24 compiled `foreign/idr/`
  with no change for them. It did on arm64 macOS (below, "Adopted in the
  cutover"); recheck when `.toolchain/llvm-musl` is rebuilt at the pin.
- **`llvm-force-enable-stats`: retired in the cutover.** At 7208ba24,
  `Statistic` is still a no-op under `NDEBUG` unless
  `LLVM_FORCE_ENABLE_STATS` is set (read:
  `llvm/include/llvm/ADT/Statistic.h:35-42`, `:132-157`, `:159-163`):

  ```c++
  #if !defined(NDEBUG) || LLVM_FORCE_ENABLE_STATS
  #define LLVM_ENABLE_STATS 1
  #else
  #define LLVM_ENABLE_STATS 0
  #endif
  ...
  #if LLVM_ENABLE_STATS
  using Statistic = TrackingStatistic;
  #else
  using Statistic = NoopStatistic;
  #endif
  ```

  The installed `llvm-config.h` still defines the macro every time:
  `#cmakedefine01 LLVM_FORCE_ENABLE_STATS`
  (read: `llvm/include/llvm/Config/llvm-config.h.cmake:84`). It is 0 unless
  the LLVM build sets the CMake option of that name (read:
  `llvm/cmake/modules/HandleLLVMOptions.cmake:1635`). `mlir::Pass::Statistic`
  still derives from `llvm::Statistic` (read: `mlir/include/mlir/Pass/Pass.h:134`),
  so the layout still depends on the includer's `NDEBUG`.

  We control the way to retire it. At 23.1.2, neither stage-2 recipe in
  `tools/bootstrap.sh` (`args_stage2_linux`, `args_stage2_darwin`) passed
  `-DLLVM_FORCE_ENABLE_STATS=ON`; the cutover added it to both. Both build
  with `LLVM_ENABLE_ASSERTIONS=ON`, so LLVM's own statistics already
  counted, and the option costs LLVM nothing (read). With the option set,
  the installed header says 1, so `lib/Support/EnableStatistics.h` and its
  two `-include`s in `foreign/idr/CMakeLists.txt` went. The
  `static_assert` in `lib/Support/Statistics.cppm` stays, as the check.
  **Adopted:** the cutover's stage-2 build was rebuilt once with the
  option, and `.toolchain/llvm-macos`'s installed `llvm-config.h` defines
  `LLVM_FORCE_ENABLE_STATS` as 1 (read); the entry, `EnableStatistics.h`
  and its `-include`s are gone. The Linux recipe has the option, but
  `.toolchain/llvm-musl` is not yet built with it.
- **`clang-no-reflection`: keep.** The clang of 7208ba24 has the
  `-freflection` flag (read: `clang/include/clang/Options/Options.td:4158-4162`),
  but no P2996:
  - `^^` takes builtin types only (read: `clang/lib/Parse/ParseReflect.cpp:19-50`,
    "Only supports builtin types for now");
  - a reflection is `Null` or `Type` (read: `clang/include/clang/AST/Reflection.h`,
    `enum class ReflectionKind { Null, Type }`);
  - there are no splices: `CXXReflectExpr` is the only reflection node
    (read: `clang/include/clang/Basic/StmtNodes.td:190-191`), and no splice
    token or parser exists;
  - `libcxx/include/meta` does not exist, and libc++'s status row for
    P2996R13 is empty (read: `libcxx/docs/Status/Cxx26Papers.csv:120`);
  - clang's own status page lists P2996R13 and its companion papers as "No"
    (read: `clang/www/cxx_status.html:406-430`), and
    `clang/docs/ReleaseNotes.md` does not mention reflection.

## Every other entry, at 7208ba24

- **`remove-dead-values-unreachable`, `remove-dead-values-address-taken`:
  keep the patch.** #208881 is not on main. `RemoveDeadValues.cpp` changed
  in other ways (read):
  - it no longer touches the pass root (`:813`, `:843`);
  - it skips a function whose users it cannot all see (`:281`,
    `SymbolUserMap::areAllUsesVisible` at `mlir/include/mlir/IR/SymbolTable.h:420`);
  - it maps callee results through `getForwardedResults` (`:344`, `:370`);
  - it erases operands with `RewriterBase::eraseOperands`;
  - it canonicalizes each root region with an explicit scope (`:838-866`).

  None of these gives the remaining uses of an erased value a definition.
  Nor does main keep a call the pass erases no result of:
  `RewriterBase::eraseOpResults` still builds a new op when nothing is to be
  erased (read: `mlir/lib/IR/PatternMatch.cpp:278-314`, no early return),
  and the pass still calls it for every listed call (read:
  `RemoveDeadValues.cpp:201-209`, `:733`). `idr-dead-values` ran the pass
  on a copy for that. Proposal 0002 replaced it with a patch of its own,
  `upstream/16-remove-dead-values-unchanged-call`, which makes
  `eraseOpResults` keep an op it erases no result of, and the simplify
  round now runs `remove-dead-values{canonicalize=false}` directly.
- **`mlir-recursion`: keep.** The parser still recurses per level of
  nesting (read: `mlir/lib/AsmParser/AttributeParser.cpp:49`, `:74`). The
  printer's attribute recursion is unchanged; its diff touches properties,
  resources, a new float type, the signs of affine constants and two
  operand helpers. `AttrTypeSubElements.h` and
  `mlir/IR/Visitors.h` are unchanged. `tests/upstream/recursive-attribute-parser`,
  which runs on every target, still reproduces at the pin on arm64 macOS
  (measured, 2026-10-09: it printed `nested: still reproduces`; 1,000
  deep parses on an 8 MiB stack, 100,000 deep ends `mlir-opt` with a
  signal). It has not run on x86_64 Linux at the pin.
- **`bytecode-deferred-quadratic`: keep the patch.**
  `mlir/lib/Bytecode/Reader/` is identical in the two trees (read). Only the
  writer changed, and only for properties.
- **`simplify-structural-fixpoint`: keep the patch; the loop is now the
  upstream pass, with `on-convergence-failure=silent`.**
  `composite-fixed-point-pass` has `on-convergence-failure` with values
  `warn`, `error` and `silent` (read:
  `mlir/include/mlir/Transforms/Passes.td:615-626`;
  `mlir/include/mlir/Transforms/CompositePass.h:16`;
  `createCompositeFixedPointPass` in `mlir/include/mlir/Transforms/Passes.h:94-98`;
  the switch at `mlir/lib/Transforms/CompositePass.cpp:79-95`). What the
  adoption had to weigh (read; what it chose is below, "Adopted in the
  cutover"):
  - the pass still decides by `OperationFingerPrint` (`CompositePass.cpp:71`,
    `:97-99`);
  - it checks the budget before the fingerprint: it runs the pipeline
    `max-iterations` + 1 times before it gives up, and does not look at
    what the last run changed (`:79-99`);
  - it refuses a `max-iterations` of 0 or less when it is initialized
    (`:57-63`);
  - the error text is its own, `Composite pass "<name>"+ didn't converge in
    <n> iterations` (`:80-83`), not `unsupported (compile-time budget)`;
  - it has no hook per iteration, so the round trace
    (`Simplify/Trace.cppm`) and the round's statistics
    (`support::PipelineStatistics`) have to come from passes of ours inside
    the pipeline it runs.

  `mlir/lib/Transforms/SCCP.cpp` is identical in the two trees, so
  `upstream/02-composite-fixed-point-sccp` is still needed.
- **`forward-dataflow-callee-lookup`: keep the patch.** The forward analyses
  still call `resolveCallable()` (read:
  `mlir/lib/Analysis/DataFlow/SparseAnalysis.cpp:237`,
  `DenseAnalysis.cpp:104`; DenseAnalysis is unchanged).
- **`inline-unreachable`: keep the patch.** The `ub` dialect is unchanged.
  The only change to `InliningUtils.cpp` is that it refuses a call whose
  results are not all forwarded (read: `:490-494`).
- **`vectorize-precondition-body`: keep the patch.** The precondition's rule
  is unchanged, and its lines moved (read: `Vectorization.cpp:2269`,
  `:2295`, `reductionPreconditions` at `:1881`).
- **`int-range-narrowing-exactness`:** main narrows a shift only when its
  amount stays below the width (read: `IntRangeOptimizations.cpp:405-409`).
  The remainders are still narrowed by the same rule (`:385-404`).
  `DeleteTrivialRem` now accepts any nonzero unsigned modulus (`:205-247`).
  That is a separate change. The remainder cases of `upstream/09` were
  rerun on an unpatched main at 7208ba24 (measured): two of the three
  still narrow where they must not, so the patch stays, now for the
  remainders only (`upstream/09-int-range-narrowing-exactness/README.md`,
  "Testing on main").
- **`uplift-final-counter`: delete idris-mlir-opt's copy of the test pass.**
  On main, `test-scf-uplift-while-to-for` is still only a test pass (read:
  `mlir/test/lib/Dialect/SCF/TestUpliftWhileToFor.cpp:26`), and no
  non-test pass applies `populateUpliftWhileToForPatterns`. With
  `tests/upstream/uplift-final-counter` deleted, nothing in the tree runs
  the pass: before the cutover, a grep named it only in
  `foreign/idr/tools/idris-mlir-opt.cc` and PINS.md. The struct
  (`idris-mlir-opt.cc:21-39` before the cutover), its registration
  (`:50`), its include of `mlir/Dialect/SCF/Transforms/Patterns.h` and the
  `PIN(uplift-final-counter)` marker go with the entry.
- **`mlir-cxx-api`: unchanged.** There is no module unit (`.cppm`, `.ixx`)
  and no `export module` in `mlir/` or `llvm/include/` (read).
- **`cmake-module-restat`: unchanged.** The diff of `clang/lib/Frontend` and
  `clang/lib/Serialization` shows no clang change that leaves an unchanged
  BMI untouched (read). The CMake half of the condition does not depend on
  LLVM.
- **`clang-module-layout-forward-declaration`, `clang-module-predeclared-new`:**
  the sources cannot decide these. The UNREACHABLE is still there (read:
  `clang/lib/CodeGen/CGExprCXX.cpp:1434`), but whether the units reach it
  is for `tests/upstream/clang-module-*` to say, run against the stage-2
  clang. On arm64 macOS that settled one: the report's unit of
  `clang-module-predeclared-new` compiles, and the entry is retired.
  `clang-module-layout-forward-declaration`'s
  check runs on x86_64 Linux alone and has not run at the pin (below,
  "Adopted in the cutover").
- **`darwin-ld64-tapi`:** handled in the cutover (main has `arm64e.x1`;
  the `SkipUnknownTriples` change stays).
- **`while-move-if-down-duplicates`:** retired in the cutover with
  `upstream/14-while-move-if-down-duplicates` (main has the fix).
- **Not tied to the LLVM pin, and unchanged by it:** `zones-on-demand`,
  `platform-gate-x86_64`, `versions-in-lock-file`, `no-stdexec`,
  `darwin-inert-mitigations`, `cmake-import-std-uuid`, `clang-libcxx`,
  `no-sanitizer-runtimes`, `musl-thread-stacks`, `stage2-thinlto`,
  `runtime-quarantine`, `runtime-cx16`, `simdutf-dispatch`,
  `linux-uapi-from-host`, `mirrored-sources`, `idris-support-host-cc`.

Some workarounds carry no PIN marker. Checked against the same diff:

- **`Support/Statistics.cppm` (`PipelineStatistics`):** the pass manager
  still does not print the statistics of a pipeline that a pass runs
  dynamically. `PassStatistics.cpp` was only refactored.
- **`Support/TaggedAction.cppm`'s `SelfOwningTypeID`:** `TypeID.h` is
  unchanged.
- **`Eval/Jit.cppm`'s own LLJIT:** `mlir::ExecutionEngine` still links
  through RuntimeDyld (read: `mlir/lib/ExecutionEngine/ExecutionEngine.cpp:26`, `:320`).
- **`Canonicalize/*`'s copy of canonicalize's driver and options:**
  `Canonicalizer.cpp` and the greedy driver are identical in the two trees.
  The way out that `substrate.md` §4 names,
  `createCanonicalizerPass(GreedyRewriteConfig)` with a listener, was
  already available at 23.1.2. It is W3's work, not the bump's.

## Trunk mechanisms, and what each could replace

1. **`composite-fixed-point-pass` `on-convergence-failure`.**
   - Replaces: `idr-simplify`'s own loop (`Simplify/Pass.cc`).
   - Verdict: **adopted**, with `silent`, not `error` (above, and
     "Adopted in the cutover").
2. **Strict property assembly formats, on by default.**
   - What: a declarative format must bind every inherent attribute or
     include `prop-dict`, and `attr-dict` carries discardable attributes
     only (read: `mlir/include/mlir/IR/DialectBase.td:58-63`;
     `mlir/tools/mlir-tblgen/OpFormatGen.cpp:3609-3625`;
     `mlir/docs/DefiningDialects/_index.md:275-291`).
   - Fit: this is the rule AGENTS.md keeps for facts. A fact the format
     must name cannot ride along in `attr-dict` with the discardable ones.
   - Replaces: nothing. The `idr` dialect gets it with the bump.
   - Verdict: **adopt now**, by meeting it. Do not set the deprecated
     `useStrictPropertiesInAssemblyFormat = 0`. `IdrOps.td` has 82
     `attr-dict` uses, and mlir-tblgen names each op that is missing an
     attribute. The generated parsers also reject an inherent attribute
     written in an op's `{...}` (read:
     `mlir/docs/DefiningDialects/_index.md:280-282`), so a test
     input in the custom form that writes one there stops parsing.
   - Unaffected: Emit writes the generic form, and the parser still accepts
     inherent attributes in a generic op's dictionary (read:
     `mlir/lib/AsmParser/Parser.cpp:1587-1592`).
3. **The enum attribute's default format is `` `<` $value `>` ``.**
   - What: the new default (read: `mlir/include/mlir/IR/EnumAttr.td:570`).
     Arith deleted its two identical overrides (read:
     `mlir/include/mlir/Dialect/Arith/IR/ArithBase.td:145`, `:166`).
   - Replaces: `Idr_EffectAttr`'s override (`IdrOps.td:288-290`), which is
     that default, spelled a second time.
   - Verdict: **adopt now**. Delete the `let assemblyFormat`.
4. **The region-branch canonicalization patterns take `IsolatedFromAbove`
   ops.**
   - What: three asserts removed, and a replacement never crosses the
     boundary (read: `mlir/lib/Interfaces/ControlFlowInterfaces.cpp:732`,
     `:763-766`).
   - Replaces: no code of ours. None of our region-branch ops is isolated.
   - Verdict: **later**, if W6's regions become isolated region-branch ops
     (conjecture that they would).
5. **`MLIRContext::TransientScope`.**
   - What: types and attributes created inside the scope are pruned when
     it ends. No dialect may be loaded inside, no IR may still refer to
     them, and the scope begins and ends outside any multi-threaded
     execution (read: `mlir/include/mlir/IR/MLIRContext.h:149-190`;
     `mlir/lib/IR/MLIRContext.cpp:688`).
   - Could serve: `idr-eval`'s scratch modules (`Eval/Scratch.cppm`) and
     `idr-narrow-lanes`' trial copies (`Narrow/Copy.cppm`). Their uniqued
     constants and types outlive them in the context.
   - Replaces: no workaround.
   - Verdict: **later**, on a measurement of the context's growth in a long
     compile, and only where the preconditions hold.
6. **LLVM's remarks into MLIR's remark engine.**
   - What: `remark::LLVMToMLIRDiagnosticHandler` and
     `remark::importLLVMRemarks` (read:
     `mlir/include/mlir/Remark/LLVMRemarkImport.h:40`, `:50`;
     `mlir/docs/Remarks.md`, "Importing LLVM Remarks").
   - Could serve: the driver runs LLVM's O3 (`Target/Optimize.cppm`,
     `Driver/Run.cppm`) with no diagnostic handler, so `--remarks` and
     `--remarks-file` show none of LLVM's remarks (the vectorizer's, the
     inliner's). Installed on the `LLVMContext`, the handler would file them
     as `llvm-<pass>`, and a backend error would become an MLIR diagnostic
     that `Verdict` counts.
   - Replaces: no workaround. It is a new feature, and 0003 keeps new
     features out of the cutover.
   - Verdict: **later**.
7. **`OperationName::walkInherentAttrs`.**
   - What: visits an op's inherent attributes without building a dictionary
     (read: `mlir/include/mlir/IR/OperationSupport.h:454-458`). Upstream
     moved its own walks to it, with `getRawDictionaryAttrs` (AsmPrinter,
     CallGraph, the bytecode writer).
   - Could serve: five walks of ours call `getAttrDictionary()`, which
     builds and uniques a new `DictionaryAttr` for an op with properties:
     `Verify/Program.cppm:101`, the `Layouts` constructor's walk for
     closure labels (`Layout/Layouts.cppm`),
     `Graph/References.cppm:74`, `Ownership/Borrow.cppm:54`,
     `Facts/Infer.cppm:66`.
   - Verdict: **later**, on a measurement of compile time or memory.
8. **The inliner blocks recursive edges across iterations.**
   - What: once an edge meets its own inline history, the rest of that
     inliner run does not inline it (read:
     `mlir/lib/Transforms/Utils/Inliner.cpp:476-487`, `:641-646`,
     `:711-713`).
   - Replaces: nothing. The loop breakers stay. The block lasts one run, so
     one round, and it sees only calls. The breakers cut cycles of
     references, closures included, across rounds (`Simplify/Breakers.cppm`).
   - Verdict: **no**. It is also a behaviour change, below.
9. **ODS resources with effect parameters.**
   - What: `Resource<name, parameters>` puts a parameters attribute on a
     declared effect (read:
     `mlir/include/mlir/Interfaces/SideEffectInterfaceBase.td:25-30`, `:184`;
     `mlir/tools/mlir-tblgen/OpDefinitionsGen.cpp:3577`).
   - Replaces: no hand-written `getEffects`. The effect W3 wants (S2.1) is
     conditional on the grade, and a declared effect cannot be.
   - Verdict: **no**.
10. **`getForwardedResults` and `call_interface_impl::verifyCallOpInterface`.**
    - What: a call's results that come from the callee, and a shared check
      of a call against its callee (read:
      `mlir/include/mlir/Interfaces/CallInterfaces.td:144`;
      `mlir/include/mlir/Interfaces/CallInterfaces.h:47-59`).
    - Replaces: nothing. `idr.apply` forwards every result, and its callee
      is a value, so the shared check finds no callable to compare.
    - Verdict: **no**.
11. **Smaller ones.**
    - What:
      - `RewriterBase::eraseOperands` (read:
        `mlir/include/mlir/IR/PatternMatch.h:553`);
      - `RemarkEngine::isRemarkEnabled`, new, and the queries per remark
        kind, now public (read: `mlir/include/mlir/IR/Remarks.h:560-597`);
      - the data-flow solver no longer queues a work item twice (read:
        `mlir/include/mlir/Analysis/DataFlowFramework.h:413-470`).
    - Replaces: nothing of ours. No code of ours erases operands, and the
      `InFlightRemark` test (`Simplify/Trace.cppm`) already suffices. The
      worklist change should speed up `sccp`, `int-range-optimizations`
      and our analyses at no cost (conjecture, not measured).
    - Verdict: **no** for the first two; the third comes with the bump.

The survey also found two items that do not depend on the bump. They are
listed because the diff showed them:

- **`Canon/Feeds.cppm:55-79` (`foldsWith`) copies upstream's fold
  simulation from before upstream fixed it.** Upstream's fix (read:
  `mlir/lib/Analysis/DataFlow/ConstantPropagationAnalysis.cpp:69-98`) says
  that "`fold` can mutate the operation in place and still return an
  out-of-place result". So it restores the operands (only if changed), the
  discardable attributes and the properties, whatever `fold` returned.
  Ours restores only after an in-place fold, and through
  `setAttrs(getAttrDictionary())`, which cannot clear a property that the
  fold set. Whether a folder of ours mutates and also returns a result is
  not known (conjecture). Every call the fix needs exists at 23.1.2.
  **Not in the cutover:** it is a gap in our copy, not a trunk mechanism,
  so it is separate work (below, "Adopted in the cutover").
- **`Lower/Runtime.cppm:61` declares `noreturn` through `passthrough`.**
  `llvm.func` has a `noreturn` unit attribute at 23.1.2 and at 7208ba24
  (read: `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:2147`).
  `setNoreturn(true)` would say it the one way. **Adopt** whenever that
  file is next touched.

## What the build met

The survey crossed these API and behaviour changes, written before the
build; the port of `foreign/idr` to main met them on arm64 macOS. The
list is not complete.

- **The toolchain was rebuilt once.** The cutover's stage-2 build was
  rebuilt with `LLVM_FORCE_ENABLE_STATS=ON` added to both recipes, so
  that the installed `llvm-config.h` says statistics count (above,
  `llvm-force-enable-stats`). That build is the one that stands:
  `.toolchain/llvm-macos`, stamped at 7208ba24 with 02-07, 09 and 15
  (2026-10-09T04:21Z, 1836 s on 12 jobs).
- **Symbol ops:** `SymbolOpInterface` no longer implements `getNameAttr` or
  `getVisibility` by default (read: `mlir/include/mlir/IR/SymbolInterfaces.td:34`, `:45`).
  - An op with `Symbol` takes the `SymbolName` and `SymbolVisibility`
    traits (`:250`, `:253`), or implements them itself. For us that is
    `Idr_DataOp` (`IdrOps.td:347`) and `Idr_CtorOp` (`:368`).
  - `setName` is deprecated in favour of `setSymbolName` (`:148-157`).
  - `SymbolTable::getVisibilityAttrName` is gone. `getSymbolAttrName`
    remains as a compatibility alias, which
    `Canonicalize/Counted.cppm:32` still uses. Upstream reads the name
    through `SymbolOpInterface` instead
    (`mlir/lib/Pass/IRPrinting.cpp:73-74`).
- **Strict formats and the enum default:** mechanisms 2 and 3 above.
  `func.call` and `builtin.module` now print through `prop-dict` (read:
  `mlir/include/mlir/Dialect/Func/IR/FuncOps.td:123`;
  `mlir/include/mlir/IR/BuiltinOps.td:61`). A test that reads a call's
  `no_inline` from text will see it there.
- **Inliner:** mechanism 8 can change what `idr-inline` inlines, since its
  iterations run until nothing is inlined. The suites are the check: on
  arm64 macOS all of them pass at the pin. The five tests `make test`
  first failed there failed the same way on 23.1.2: bugs of ours from the
  lazy-streams merge (2726706c), not the cutover's, fixed on their own.
- **`scf.for` value bounds:** the closed form of a loop's result now needs
  `ub > lb` proven, and the induction variable of an unsigned loop gets no
  bounds (read: `mlir/lib/Dialect/SCF/IR/ValueBoundsOpInterfaceImpl.cpp:104-111`,
  `:129-133`). `Graph/Trips.cppm` bounds the span `ub - lb` of the bounds
  themselves, so it is unaffected (read).
- **LLVM IR text:** metadata keeps persistent numbers, and `Module::print`
  no longer renumbers them (read: `llvm/docs/ReleaseNotes.md`, "Changes to
  the LLVM IR"). `--emit llvm` prints with `llvmModule->print`
  (`Driver/Run.cppm`). A test that compares that text needs
  `Module::renumberMetadataForAssembly()` before printing (conjecture that
  any such test exists).
- **`TargetOptions::AllowFPOpFusion` is gone**, with `FPOpFusion` (read:
  `llvm/include/llvm/Target/TargetOptions.h`). Our `FPOpFusion::Strict`
  went from `Target/TargetOptions.cppm`: at 23.1.2 it only split
  `llvm.fmuladd` into a multiply and an add, and main fuses a multiply and
  an add only where the IR allows it (a `contract` flag, or `llvm.fmuladd`),
  which neither the lowering nor the runtime (`-ffp-contract=off`) writes.
- **`TargetMachine::createDataLayout`** is still there (read:
  `llvm/include/llvm/Target/TargetMachine.h:225`). Upstream's own callers
  moved to `Triple::computeDataLayout`. Nothing of ours has to.

## Citations that moved

These upstream line references point elsewhere at 7208ba24; the record
step updated each:

- **PINS.md `simplify-structural-fixpoint`:**
  - `CompositePass.cpp:68-91` is now `:69-103`;
  - `OperationSupport.cpp:933-975` is now `:986-1028`;
  - `SCCP.cpp` is unchanged.
- **PINS.md `remove-dead-values-unreachable`:**
  - `RemoveDeadValues.cpp:649` is now `:661`;
  - `:833` is now `:862`.
- **PINS.md `vectorize-precondition-body`:**
  - `Vectorization.cpp:2250-2288` is now `:2295-2333`;
  - `:1879-1896` is now `:1881-1898`;
  - `:1380-1382` is unchanged.
- **PINS.md `int-range-narrowing-exactness`:**
  `IntRangeOptimizations.cpp:378-397` is now `:385-409` (the entry now
  cites the cast kinds alone, `:396-402`).
- **`foreign/idr/lib/Simplify/Breakers.cppm:12`:** `Inliner.cpp:709-715` is
  now `:725-731`. The comment now names `Inliner::Impl::shouldInline` in
  place of the lines, which will not move again.

`BytecodeReader.cpp:1371-1459` (PINS.md `bytecode-deferred-quadratic`) has
not moved: the reader is the same file in both trees, and those lines are
still `resolveEntry` (read).

## Adopted in the cutover

- **`composite-fixed-point-pass` with `on-convergence-failure`:** adopted.
  `idr-simplify`'s loop is the upstream pass over the round
  (`max-iterations` = `max-rounds`). It runs with
  `on-convergence-failure=silent`, not `error`: `error` reports the pass's
  own text, which is not the user error `unsupported (compile-time
  budget)`, and replacing a diagnostic in flight is a guess about where it
  came from. The pass stops right after the round past its budget, so a
  loop that closed more than `max-rounds` rounds is the budget's, and
  `idr-simplify` says so. A pass that fails in that extra round reports
  its own error, as in any round. The upstream pass refuses a budget of
  0, so `max-rounds=0` gives the budget error without running the loop.
  Two passes of ours open and close each round for
  the count, the trace and the fixpoint remark, and the round's statistics
  are declared from the pipeline the pass is given. Still missing upstream:
  a hook per iteration, a failure the caller can name, and a decision on
  the round past `max-iterations` that it runs and does not look at
  (PINS.md `simplify-structural-fixpoint`).
- **Strict property assembly formats:** adopted. `idr.apply`'s format
  binds `arg_attrs` and `res_attrs` with an `oilist`, as main's
  `func.call_indirect` does; no op opts out of strict formats.
- **`Idr_EffectAttr`'s format override deleted:** adopted; main's
  `EnumAttr` default is the same format.
- **idris-mlir-opt's copy of `test-scf-uplift-while-to-for` deleted**, with
  PINS.md `uplift-final-counter`: done; nothing else ran it.
- **`Canon/Feeds.cppm` restores after every simulated fold**, as upstream's
  constant propagation does: not in the cutover. It is no upstream
  mechanism we can call (the fix is inside `ConstantPropagationAnalysis.cpp`)
  but a gap in our own copy of the pattern, so it is separate work, with a
  test of a folder that both changes its op and returns a result.
- **`clang-module-predeclared-new`:** retired, fixed on main. Its check
  crashed the clang of 23.1.2 on arm64 macOS as on x86_64 Linux; the clang
  of 7208ba24 compiles the report's `Retarget.cppm` in place on arm64
  macOS, with the build's own command, so the report, its check and the
  `SmallString` workaround went. The fixing commit is not identified.
  Verified on arm64 macOS only; recheck on x86_64 Linux when
  `.toolchain/llvm-musl` is rebuilt at the pin.
- **`clang-module-layout-forward-declaration`:** not rerun on the new pin.
  It crashes only the x86_64 Linux build (its check runs on Linux alone;
  the clang of 23.1.2 compiled the unit on arm64 macOS too), and the
  cutover was built and tested on arm64 macOS. The report stays.
- **`llvm-cxx17-headers`:** retired. The stage-2 clang of 7208ba24
  compiled all of `foreign/idr` and the runtime on arm64 macOS (the
  `dev-darwin` preset, 1040 steps) with no change for LLVM's headers; the
  changes the port made are API changes, listed under "What the build
  met". Verified on arm64 macOS only; recheck on x86_64 Linux when
  `.toolchain/llvm-musl` is rebuilt at the pin.
