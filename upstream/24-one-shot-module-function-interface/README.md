<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][bufferization] One-Shot Module Bufferize knows only func.func and builtin.module, refuses a function that never returns, does not analyze a cycle of calls, and writes a buffer a callee returns that is not writable

On llvm main at 7208ba24 (the pin), One-Shot Module Bufferize
(`-one-shot-bufferize="bufferize-function-boundaries"`,
`runOneShotModuleBufferize`) has five defects that meet in this compiler:

1. It bufferizes the boundaries of `func.func` alone. A dialect with function,
   call and return ops of its own (ops that implement `FunctionOpInterface`,
   `CallOpInterface` and `ReturnLike`) cannot have its calls analyzed across
   them. The driver collects `func::FuncOp`, walks `func::CallOp`, keys its
   analysis state by `func::FuncOp`, and its function-argument type converter
   takes a `func::FuncOp`. The models of the boundary are written on
   `func::FuncOp`, `func::CallOp` and `func::ReturnOp`, so another dialect
   must write the models again, and they drift.
2. It refuses a function none of whose blocks returns (every block ends in
   `ub.unreachable`), though such a function has no result that could alias
   anything.
3. It does not analyze the boundaries of functions that call each other
   circularly (a recursive function is one). A call of such a function is
   assumed to read and write every operand and to return any of them, so a
   caller that reads its tensor after a recursive call passes a copy, at
   every level of the recursion. Once defect 4 is fixed, such a call's
   result is also not writable, so each level of a recursion that writes
   what the level below returns copies it.
4. A call result is writable whatever its callee returns. A function may
   return the buffer of a constant, a `memref.get_global` of a constant
   global, or any other buffer that is not writable. A caller that writes the
   result in place then writes that buffer: the constant's global, which the
   next call returns changed, and which is read-only memory once lowered.
   Once the call's model says so, the analysis must not take a result that
   is the buffer of the call's own operand for one that may not be
   writable: `OneShotAnalysisState::isWritable` asks the op of every value,
   under a TODO ("Out-of-place bufferized value could be considered
   writable"), and alias sets are coarser than equivalence.
5. Two parts of the module path test for `builtin.module` where they mean a
   symbol table. Empty tensor elimination
   (`eliminateEmptyTensors(RewriterBase &, Operation *)`) analyzes function
   boundaries only when its op is a `ModuleOp`. `getGlobalFor` puts a
   constant's global at the top of the enclosing `ModuleOp`, not in the
   nearest symbol table, where the `memref.get_global` that reads it looks it
   up.

The compiler's functions are `idr.func`, its calls `idr.call` and its
returns `idr.return`. Its program is `idr.program`, a symbol table nested in
the module, which idr-bufferize, a pass on that op, bufferizes. A linear
array threaded through a call is written in place across it only if the
callee's boundary is analyzed, a function that crashes ends in
`ub.unreachable`, and Idris functions recurse. A constant array a function
returns must be copied before a caller writes it. A pass on the program may create a constant's global
only inside the program: it may not touch the module, and the program's
`memref.get_global` resolves there.

## Reproduce

`no-return.mlir`, upstream dialects only:

```mlir
func.func private @never_returns(%t: tensor<4xf32>) -> tensor<4xf32> {
  ub.unreachable
}

func.func @caller(%t: tensor<4xf32>, %c: i1) -> f32 {
  %c0 = arith.constant 0 : index
  scf.if %c {
    %0 = func.call @never_returns(%t) : (tensor<4xf32>) -> tensor<4xf32>
  }
  %1 = tensor.extract %t[%c0] : tensor<4xf32>
  return %1 : f32
}
```

```
$ mlir-opt no-return.mlir -one-shot-bufferize="bufferize-function-boundaries"
no-return.mlir:1:1: error: cannot bufferize func.func without func.return
```

`non-writable-result.mlir`, upstream dialects only:

```mlir
func.func private @constant() -> tensor<3xi64> {
  %c = arith.constant dense<[1, 2, 3]> : tensor<3xi64>
  return %c : tensor<3xi64>
}

func.func @writes_constant(%v: i64) -> tensor<3xi64> {
  %c0 = arith.constant 0 : index
  %0 = func.call @constant() : () -> tensor<3xi64>
  %1 = tensor.insert %v into %0[%c0] : tensor<3xi64>
  return %1 : tensor<3xi64>
}
```

With `-one-shot-bufferize="bufferize-function-boundaries"`, `@constant`
returns `memref.get_global @__constant_3xi64`, and `@writes_constant`
stores `%v` into the result of the call, which is that global: no
`memref.alloc`, no `memref.copy`. A call result is writable by the
interface's default (`BufferizableOpInterface.td:460-466`), and the call's
model does not override it.

`definite-alias.mlir`, upstream dialects only, with the fix of defect 4:
`@pick` returns its argument, whose alias set also holds a constant through
an `scf.if` that may yield either, so the callee's analysis records the
result as possibly not writable, though it is equivalent to the argument. A
caller that writes the call result then copies it, though the result is the
buffer of its own operand, its argument, which is writable and not read
after the call. At the pristine pin there is no copy, because a call result
is writable by default; no other op at the pin has a model that says a value
with a definite aliasing OpOperand is not writable, so this is reached only
through the call model, and is part of this patch.

`recursive-read.mlir`, upstream dialects only: `@foo` calls itself with its
argument and reads the argument afterwards. With
`-one-shot-bufferize="bufferize-function-boundaries"` the pin allocates a
copy of the argument and passes it to the call, though the call never
writes it: the pin's own test of this case in
`one-shot-module-bufferize.mlir` ("A recursive function") checks for that
copy, under a comment that the analysis cannot handle recursion.

`recursive-result.mlir`, upstream dialects only: each level of `@build`
writes the array the level below returns. At the pin the call result is
writable by the interface's default, so it is written in place; with the
fix of defect 4 alone, a result of a callee that is not analyzed is not
writable, and `@build`, on a cycle of calls, copies the array at every level.

`symbol-table.mlir`, upstream dialects only: a `gpu.module` holding a
function that fills its argument and returns it, and a caller that passes it
a `tensor.empty` and inserts the result into a slice of its own argument.
With `--pass-pipeline='builtin.module(gpu.module(eliminate-empty-tensors))'`
the `tensor.empty` stays. The analysis ran without function boundaries,
since a `gpu.module` is no `ModuleOp`, so the call is an unknown op and the
chain from the inserted value back to the empty tensor stops at it. On a
`builtin.module` the same functions have the empty tensor replaced by the
slice.

The rest of defect 1 has no reproducer in upstream dialects: no function op
but `func.func` has a `BufferizableOpInterface` implementation, which is the
bug. The pass's own test, below, attaches the func dialect's models to the
test dialect's `test.conversion_func_op`, `test.conversion_call_op` and
`test.return`, which only the patch makes possible, and it fails without the
change. `idr-call.mlir` is the same in this repository's dialect, together
with defects 4 and 5 on `idr.program`.

`idr-cycle.mlir` is `recursive-result.mlir` in this repository's dialect.

`named-sequence.mlir` is the case that made upstream revert its own
generalization: a payload `func.func` and a `transform.named_sequence` side
by side at the top of one module. The pin bufferizes it; the patch must
too.

(The texts above are read from the source. No `mlir-opt` of the pin was at
hand to run them.)

## Expected

- The driver bufferizes the boundary of every function op it has an
  implementation for, through `FunctionOpInterface`, `CallOpInterface` and
  the `ReturnLike` trait, as `OwnershipBasedBufferDeallocation` already takes
  `FunctionOpInterface`. The implementations of the func dialect are written
  on those interfaces, so any dialect attaches the same ones to its function,
  call and return ops. A function op without an implementation is bufferized
  like any other op, as at the pin.
- A function that never returns has no result that aliases or is equivalent
  to an argument, and bufferizes.
- The boundaries of functions that call each other circularly are
  analyzed: a call into the cycle reads, writes and aliases what the
  callee's body does, so a recursive function that reads its argument after
  calling itself passes it without a copy, and a recursion that writes what
  the level below returns writes it in place.
- A call result is writable only when the callee is analyzed and returns, as
  that result, no buffer that is not writable. Otherwise the caller copies
  before it writes. A value that definitely aliases one of its op's
  OpOperands, as a call result equivalent to an argument does, is writable
  on its own: in place it is that OpOperand's buffer, checked through its
  alias set; out of place it is the copy.
- Empty tensor elimination analyzes function boundaries on any symbol table,
  and a constant's global is a symbol of the nearest symbol table.

## Cause

- `mlir/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`
  names `func::FuncOp` 29 times and `FunctionOpInterface` never.
  - `getFuncOpsOrderedByCalls` (`:315-378`) collects `block.getOps<func::FuncOp>()`
    (`:326`) and walks `func::CallOp` (`:329`), asserting that each callee is
    a `func::FuncOp` (`:331`).
  - The analyses (`:118-278`), `foldMemRefCasts` (`:431-467`),
    `analyzeModuleOp` (`:469-532`), `bufferizeModuleOp` (`:546-615`), whose
    "other ops" loop skips `func::FuncOp` (`:603`), and the no-analysis
    filter (`:631-639`) are typed the same way.
- `FuncAnalysisState` keys its five maps by `func::FuncOp`
  (`mlir/include/mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h:57-70`).
  The models are structs over the func dialect's ops
  (`FuncBufferizableOpInterfaceImpl.cpp:162-535`, `cast<func::CallOp>` at
  `:167`, `:182`, `:197`, `:232`, `:258`, `func::CallOp::create` at `:336`,
  `cast<FuncOp>` at `:390`, `:418`, `:440`). The queries they read are
  `static` (`:66-160`), so another dialect can neither attach the models nor
  read the analysis.
- `BufferizationOptions::FunctionArgTypeConverterFn` takes a `func::FuncOp`
  (`mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:271-273`).
- `aliasingFuncOpBBArgsAnalysis` fails a function without a `func.return`
  (`OneShotModuleBufferize.cpp:139-145`), under a TODO that asks for an
  error on other `ReturnLike` ops.
- `getFuncOpsOrderedByCalls` (`:315-378`) puts every function it cannot
  order callee first (those on a cycle of calls, and those that call one)
  in one list, and `analyzeModuleOp` analyzes their bodies but runs none of
  the boundary analyses on them (`:515-529`, the TODO "We currently skip all
  function argument analyses for functions that call each other
  circularly"). The call models then answer as for a callee that is not
  analyzed: every operand read and written, every result aliasing every
  operand.
- No analysis records whether a function returns a buffer that is not
  writable, and the call model has no `isWritable`. Its results are
  therefore writable by the interface's default.
- `OneShotAnalysisState::isWritable`
  (`OneShotAnalysis.cpp:279-288`) asks the op of every value, under the
  TODO above, so a model that says a value is not writable is believed even
  where the value definitely is (a part of) an operand's buffer.
- `EmptyTensorElimination.cpp:210` takes function boundaries into account on
  `dyn_cast<ModuleOp>(op)` alone. `BufferUtils.cpp:105` places the global at
  `getParentOfType<ModuleOp>()`.

## History upstream

- llvm-project #107295, then #110322 ("[MLIR] Make `OneShotModuleBufferize`
  use `OpInterface`"), which landed on 2024-10-01 and was reverted on
  2024-10-22 by #113124 for a failing staging buildbot. Its tests had to
  move every transform-interpreter test's payload into a tagged module:
  with every `FunctionOpInterface` op a function of the driver,
  `transform.named_sequence` was one, and it has no `func.return`.
- The code owner wrote in 2025, on the Discourse thread "Is the
  bufferization of func.func able to be reused on other
  FunctionOpInterface", that the failures could be fixed.
- Upstream main past the pin was read on 2026-10-14:
  `OneShotModuleBufferize.cpp` is byte for byte the pin's. Defects 4 and 5
  were found by reading on 2026-10-15; no upstream issue for either was
  searched for yet. Defect 3 is the TODO the driver carries; no upstream
  work on it was found.

## Patch

`llvm.patch` is a `git diff` against 7208ba24. It relands #110322 on the
current driver, with its cause fixed, and fixes defects 2 to 5.

- **Functions and calls.** The driver's functions are the ops of the symbol
  table that implement both `FunctionOpInterface` and
  `BufferizableOpInterface` (`isBufferizableFunction`).
  `transform.named_sequence` has no implementation, so it stays an "other
  op", as at the pin, and no test needs a payload tag. The calls are
  `CallOpInterface` ops; one whose callee is not a function of the driver
  orders nothing, where the pin asserted.
- **The analysis state.** `FuncAnalysisState`'s maps and
  `startFunctionAnalysis` are keyed by `FunctionOpInterface`. The queries
  are exported: `getFuncAnalysisState`, `getFuncOpAnalysisState`,
  `getEquivalentFuncArgIdx`, two `getCalledFunction`s and
  `getBufferizedFunctionArgType`. `getReturnOps` returns the `ReturnLike`
  terminators as `Operation *`.
- **The models.** The three models become public templates over the
  concrete op, written on the interfaces: `func_ext::FuncOpBufferizableModel<Op>`,
  `CallOpBufferizableModel<Op>` and `ReturnOpBufferizableModel<Op>`, in
  `FuncBufferizableOpInterfaceImpl.h`. Their bodies are exported functions
  in the .cpp (`callOpBufferizesToMemoryRead`, `bufferizeCallOp`,
  `bufferizeFuncOp`, and so on).
  - The func dialect attaches them to `func.func`, `func.call` and
    `func.return`, and any dialect attaches them to its own ops.
  - A call is bufferized as a clone of itself on the buffers, where the pin
    built a `func::CallOp`.
  - A call's operand is mapped to its callee argument through
    `getArgOperands()`, so a call op with operands that pass no argument is
    handled.
  - Without the module analysis's state, the callee is not looked up: no
    function is analyzed then.
- **The type converter.** `FunctionArgTypeConverterFn` takes a
  `FunctionOpInterface`, the API change #110322 also made.
  `foldMemRefCasts` sets the type through `cloneTypeWith`. The no-analysis
  filter names a function by `SymbolTable::getSymbolName`.
- **No return.** A function with no `ReturnLike` terminator is analyzed with
  no aliasing result, where the pin failed (the TODO goes).
- **Cycles of calls.** The facts the boundary analyses record of a function
  are one value, `FuncBoundaryFacts` (its equivalences, aliases, reads,
  writes and results that may not be writable), and `FuncAnalysisState`
  maps each analyzed function to it (`boundaryFacts`, with
  `startFunctionAnalysis`, `finishFunctionAnalysis` and `getBoundaryFacts`);
  the analyses return it. `getFuncOpsOrderedByCalls` gives the strongly
  connected components of the call graph callee first (`llvm::scc_iterator`
  on the module's functions), where the pin sorted the acyclic part and
  left the rest unordered. A component that is a cycle of calls is analyzed
  by `analyzeCallCycle` (the TODO goes):
  - The facts of its functions are found first, each analysis on a
    `OneShotAnalysisState` of its own, rooted at the function, on which its
    calls see their callees' facts as analyzed. Every function starts as
    doing nothing; a function is analyzed with the facts its callees have,
    the facts it is found to have are joined into its own
    (`FuncBoundaryFacts::join`: reads, writes, aliases and results that may
    not be writable are added, equivalences that both do not have are
    dropped), and its callers in the cycle are analyzed again when its facts
    changed. The facts only grow, over the finitely many argument and result
    positions of the cycle, so the iteration ends; each function was then
    last analyzed with the final facts of its callees.
  - These analyses annotate nothing, and decide with the properties of the
    IR that the module's state found (unstructured control flow, parallel
    regions), so that they decide as the final analysis does.
  - Each function is then analyzed in the module's state, its calls in the
    cycle seeing the facts found, and its boundary is recorded as that
    analysis finds it. It must find no more than the facts its callers were
    analyzed with: the analyses that found them decide as this one does. If
    it finds more, the decisions made at the calls in the cycle rest on too
    little, so the module analysis fails with an error on the function,
    where an assertion would let a release build bufferize unsoundly.
  - `FuncAnalysisState` may share a `SymbolTableCollection` with another
    state (a second constructor), so that the analyses on states of their
    own do not build the module's symbol table again.
- **Results that are not writable.** `FuncBoundaryFacts::nonWritableReturnVals`
  records the return values whose alias set holds a value that is not
  writable. The function's own entry block arguments are left
  out, since a result that aliases one aliases the call's operand at the
  caller. A function without a body may return anything, so all of its
  tensor results are recorded. `funcOpNonWritableReturnValsAnalysis` fills
  it after each function's analysis. The call model's `isWritable` reads it,
  and it is false for a callee that is not analyzed (yet).
  `OneShotAnalysisState::isWritable` returns true for a value with an
  aliasing OpOperand that `isDefinite`, and otherwise asks the op as before
  (the TODO goes). In place, the value joins the OpOperand's alias set,
  whose values are checked through it; out of place, it is (a part of) the
  copy. The analysis order does not change this: when an OpOperand is
  decided after a write of its result, `wouldCreateWriteToNonWritableBuffer`
  collects that write among the in-place writes of the OpOperand's and its
  results' aliases, and checks both alias sets, as the scf models' "can
  always be viewed inplace" already reasons for loop arguments.
- **Symbol tables.** `eliminateEmptyTensors(RewriterBase &, Operation *)`
  runs the module analysis on any op with the `SymbolTable` trait.
  `getGlobalFor` puts the global in the nearest symbol table
  (`SymbolTable::getNearestSymbolTable`).
- `BufferizationOptions::isOpAllowed` is unchanged.

Tests:
- `one-shot-module-bufferize-function-interface.mlir` runs
  `-test-one-shot-module-bufferize`, whose pass now attaches the func
  dialect's models to the test dialect's function, call and return ops.
  It covers a callee written in place, a caller that passes its buffer, and a
  caller that reads after the call and gets a copy.
- `one-shot-module-bufferize-transform-sequence.mlir` is the revert's case.
- `one-shot-module-bufferize-no-return.mlir` is `no-return.mlir` with CHECK
  lines.
- `one-shot-module-bufferize-call-cycle.mlir` covers a recursive function
  whose result each level writes in place, a recursive function that writes
  its argument and passes it on, with a caller that passes its own buffer,
  and two functions that call each other, one of which writes its argument,
  with a caller that reads its tensor after the call and passes a copy; with
  `test-analysis-only`, the access the cycle's functions are found to have.
- `one-shot-module-bufferize.mlir`'s "A recursive function" now checks that
  no copy is made, and `one-shot-module-bufferize-analysis.mlir`'s
  `@recursive_function`, which only calls itself, that both call operands
  bufferize in place and that the function neither reads nor writes either
  argument.
- `one-shot-module-bufferize-definite-alias.mlir` is `definite-alias.mlir`
  with CHECK lines (no copy, the store into the call result), and the same
  call with the operand read after it, which bufferizes out of place, so
  the result is the copy, written in place: one copy in all.
- `one-shot-module-bufferize-non-writable-result.mlir` covers a returned
  constant copied before the caller writes it, a returned allocation written
  in place, and a call of a function without a body, whose result is copied.
- `one-shot-non-module-bufferize.mlir` gains a case: a constant's global
  inside a `test.symbol_scope_isolated`.
- `one-shot-non-module-empty-tensor-elimination.mlir` runs the elimination on
  a `test.symbol_scope_isolated` and finds the empty tensor through a call.
- The other `one-shot-module-bufferize*.mlir` files are unchanged. Writing a
  call result of a function without a body now copies, which none of them
  does; "Two functions calling each other recursively" bufferizes as before,
  since neither function reads or writes its argument.

The patch touches no file another carried patch touches, so it applies to
the pinned source alone and after the patches before it
(`tests/spec/upstream-patches`).

## Testing at the pin

Not built: no LLVM is built on the machine this was written on.
- The diff applies to the pristine pin (`git apply --check`).
- The changed .cpp files of `MLIRBufferizationTransforms` and
  `MLIRBufferizationDialect` (`FuncBufferizableOpInterfaceImpl.cpp`,
  `OneShotModuleBufferize.cpp`, `EmptyTensorElimination.cpp`,
  `BufferUtils.cpp`, `BufferizableOpInterface.cpp`) pass `-fsyntax-only`
  with the typecheck build's compile commands of the pin, the patched
  headers first on the include path.
- So does `TestOneShotModuleBufferize.cpp`, against the test dialect's
  headers generated with the typecheck build's `mlir-tblgen`.
- idr-bufferize's units, which attach the templates to `idr.func`,
  `idr.call` and `idr.return`, pass the same check.
- The cycle analysis (2026-10-15): the changed `OneShotModuleBufferize.cpp`
  and `FuncBufferizableOpInterfaceImpl.cpp` pass `-fsyntax-only` with the
  typecheck build's commands, the patched headers first; the diff applies
  to the pristine pin.
- The definite-alias rule (2026-10-15), first written as a patch of its
  own and folded in here because it does not reproduce without the call
  model: `OneShotAnalysis.cpp` passes `-fsyntax-only` the same way.

Stage 2 on each target, then the pull requests' pre-merge CI, are the first
runs. `check-mlir` has not run with it.
`tests/upstream/one-shot-module-function-interface` checks the reproducers
with the toolchain once stage 2 carries the patch.

## Upstreaming plan

Status: not filed; not built.

Four pull requests against llvm/llvm-project main, in this order, each from
its part of `llvm.patch`. The third depends on the second: a call result of
a callee that is not analyzed is not writable, so before cycles are
analyzed it would make every level of a recursion copy. The fourth does not
depend on the others. No issue for the first and second; one issue each for
the third and fourth, which are miscompiles a reader can run.

1. "[mlir][bufferization] Run One-Shot Module Bufferize on
   FunctionOpInterface", a reland of #110322. Its body names #110322 and
   #113124 by number and says what differs:
   - the function set is limited to function ops with an implementation;
   - unresolved calls are skipped;
   - the queries are exported, and the models are public templates on the
     interfaces;
   - a function that never returns is analyzed.
   Tests: function-interface, transform-sequence, no-return.
2. "[mlir][bufferization] Analyze the boundaries of functions on a cycle of
   calls": `FuncBoundaryFacts`, the components of the call graph, and
   `analyzeCallCycle`, which resolves the TODO in `analyzeModuleOp`. Tests:
   call-cycle, and the changed recursive cases of
   `one-shot-module-bufferize.mlir` and
   `one-shot-module-bufferize-analysis.mlir`.
3. "[mlir][bufferization] A call result is writable only if its callee
   returns a writable buffer": `nonWritableReturnVals`, the call model's
   `isWritable`, and the definite-alias rule in
   `OneShotAnalysisState::isWritable`, which keeps the first from copying a
   result that is its operand's buffer and resolves the TODO there. Tests:
   non-writable-result and definite-alias. The issue is
   `non-writable-result.mlir` with the store into the global.
4. "[mlir][bufferization] Use the nearest symbol table, not ModuleOp, in
   empty tensor elimination and getGlobalFor". Tests: the
   `one-shot-non-module-bufferize.mlir` case and
   one-shot-non-module-empty-tensor-elimination.

Before filing each one:
- search for an upstream fix since 7208ba24 (if one landed, that part goes
  and the pin takes it);
- check that the diff applies to then-current main and is clang-format
  clean;
- for the first, read the ArmSME integration tests
  (`mlir/test/Integration/Dialect/Linalg/CPU/ArmSME/`) for transform-driven
  bufferization, since they failed under #110322; for the second, read every
  test with `bufferize-function-boundaries` for a cycle of calls (at the pin,
  the three cases above are all of them) and measure the cost of the
  analyses on states of their own on a module with a large cycle; for the
  third, read the `one-shot-module-bufferize*.mlir` tests for a written
  result of an external callee, and every in-tree `isWritable` model for a
  value with a definite aliasing OpOperand that answers false for another
  reason than its buffer (none at 7208ba24).

`check-mlir` is each pull request's pre-merge CI's (upstream/README.md,
**CI decides**). There is no `submission.md` yet. If upstream would rather
take them as separate reports, the second, third and fourth may become
directories of their own; until then they stay one patch here, since they
meet only in this driver.

Each part goes when the pin carries upstream's fix for it; when all have,
this directory, its check and its `PINS.md` entry go. The models of
`idr.func`, `idr.call` and `idr.return` stay upstream's templates.
