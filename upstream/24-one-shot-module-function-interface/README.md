# [mlir][bufferization] One-Shot Module Bufferize knows only func.func and builtin.module, refuses a function that never returns, and writes a buffer a callee returns that is not writable

On llvm main at 7208ba24 (the pin), One-Shot Module Bufferize
(`-one-shot-bufferize="bufferize-function-boundaries"`,
`runOneShotModuleBufferize`) has four defects that meet in this compiler:

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
3. A call result is writable whatever its callee returns. A function may
   return the buffer of a constant, a `memref.get_global` of a constant
   global, or any other buffer that is not writable. A caller that writes the
   result in place then writes that buffer: the constant's global, which the
   next call returns changed, and which is read-only memory once lowered.
4. Two parts of the module path test for `builtin.module` where they mean a
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
callee's boundary is analyzed, and a function that crashes ends in
`ub.unreachable`. A constant array a function returns must be copied before
a caller writes it. A pass on the program may create a constant's global
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
with defects 3 and 4 on `idr.program`.

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
- A call result is writable only when the callee is analyzed and returns, as
  that result, no buffer that is not writable. Otherwise the caller copies
  before it writes.
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
- No analysis records whether a function returns a buffer that is not
  writable, and the call model has no `isWritable`. Its results are
  therefore writable by the interface's default.
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
  `OneShotModuleBufferize.cpp` is byte for byte the pin's. Defects 3 and 4
  were found by reading on 2026-10-15; no upstream issue for either was
  searched for yet.

## Patch

`llvm.patch` is a `git diff` against 7208ba24. It relands #110322 on the
current driver, with its cause fixed, and fixes defects 2 to 4.

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
- **Results that are not writable.** `FuncAnalysisState::nonWritableReturnVals`
  records, per function, the return values whose alias set holds a value
  that is not writable. The function's own entry block arguments are left
  out, since a result that aliases one aliases the call's operand at the
  caller. A function without a body may return anything, so all of its
  tensor results are recorded. `funcOpNonWritableReturnValsAnalysis` fills
  it after each function's analysis. The call model's `isWritable` reads it,
  and it is false for a callee that is not analyzed (yet).
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
- `one-shot-module-bufferize-non-writable-result.mlir` covers a returned
  constant copied before the caller writes it, a returned allocation written
  in place, and a call of a function without a body, whose result is copied.
- `one-shot-non-module-bufferize.mlir` gains a case: a constant's global
  inside a `test.symbol_scope_isolated`.
- `one-shot-non-module-empty-tensor-elimination.mlir` runs the elimination on
  a `test.symbol_scope_isolated` and finds the empty tensor through a call.
- The other `one-shot-module-bufferize*.mlir` files are unchanged. Writing a
  call result of a function without a body or on a cycle of calls now
  copies, which none of them does.

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

Stage 2 on each target, then the pull requests' pre-merge CI, are the first
runs. `check-mlir` has not run with it.
`tests/upstream/one-shot-module-function-interface` checks the reproducers
with the toolchain once stage 2 carries the patch.

## Upstreaming plan

Status: not filed; not built.

Three pull requests against llvm/llvm-project main, in this order, each
from its part of `llvm.patch`; the second and the third do not depend on the
first and may go in either order after it. No issue for the first; one
issue each for the second and third, which are miscompiles a reader can run.

1. "[mlir][bufferization] Run One-Shot Module Bufferize on
   FunctionOpInterface", a reland of #110322. Its body names #110322 and
   #113124 by number and says what differs:
   - the function set is limited to function ops with an implementation;
   - unresolved calls are skipped;
   - the queries are exported, and the models are public templates on the
     interfaces;
   - a function that never returns is analyzed.
   Tests: function-interface, transform-sequence, no-return.
2. "[mlir][bufferization] A call result is writable only if its callee
   returns a writable buffer": `nonWritableReturnVals` and the call model's
   `isWritable`. Test: non-writable-result. The issue is
   `non-writable-result.mlir` with the store into the global.
3. "[mlir][bufferization] Use the nearest symbol table, not ModuleOp, in
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
  bufferization, since they failed under #110322; for the second, read the
  `one-shot-module-bufferize*.mlir` tests for a written result of an
  external or recursive callee.

`check-mlir` is each pull request's pre-merge CI's (upstream/README.md,
**CI decides**). There is no `submission.md` yet. If upstream would rather
take them as separate reports, the second and third may become directories
of their own; until then they stay one patch here, since they meet only in
this driver.

Each part goes when the pin carries upstream's fix for it; when all have,
this directory, its check and its `PINS.md` entry go. The models of
`idr.func`, `idr.call` and `idr.return` stay upstream's templates.
