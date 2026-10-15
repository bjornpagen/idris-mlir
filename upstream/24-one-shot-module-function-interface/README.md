# [mlir][bufferization] One-Shot Module Bufferize knows only func.func, and refuses a function that never returns

On llvm main at 7208ba24 (the pin), One-Shot Module Bufferize
(`-one-shot-bufferize="bufferize-function-boundaries"`,
`runOneShotModuleBufferize`) bufferizes the boundaries of `func.func`
alone. A dialect with function, call and return ops of its own that
implement `FunctionOpInterface`, `CallOpInterface` and `ReturnLike` cannot
have its calls analyzed across them, though its ops may implement
`BufferizableOpInterface`: the driver collects `func::FuncOp`, walks
`func::CallOp`, keys its analysis state by `func::FuncOp`, and its
function-argument type converter takes a `func::FuncOp`. And a function
none of whose blocks returns (every block ends in `ub.unreachable`) is
refused, though it has no result that could alias anything.

The compiler's functions are `idr.func`, its calls `idr.call` and its
returns `idr.return`; a linear array threaded through a call is written in
place across it only if the callee's boundary is analyzed, and a function
that crashes ends in `ub.unreachable`.

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

(The text is the one `OneShotModuleBufferize.cpp:144` emits on the
function, read from the source; no `mlir-opt` of the pin was at hand to
run it.)

The other half has no reproducer in upstream dialects: no function op but
`func.func` has a `BufferizableOpInterface` implementation, which is the
bug. With the test dialect's `test.conversion_func_op`,
`test.conversion_call_op` and `test.return` given implementations written
as the func dialect's are, the driver still analyzes none of their
boundaries, and the pass's own test, below, fails without the change.
`idr-call.mlir` is the same in this repository's dialect.

`named-sequence.mlir` is the case that made upstream revert its own
generalization: a payload `func.func` and a `transform.named_sequence` side
by side at the top of one module. The pin bufferizes it; the patch must
too.

## Expected

The driver bufferizes the boundary of every function op it has an
implementation for, through `FunctionOpInterface`, `CallOpInterface` and
the `ReturnLike` trait, as `OwnershipBasedBufferDeallocation` already takes
`FunctionOpInterface`. A function op without an implementation is
bufferized like any other op, as at the pin. A function that never returns
has no result that aliases or is equivalent to an argument, and bufferizes.

## Cause

- `mlir/lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`
  names `func::FuncOp` 29 times and `FunctionOpInterface` never.
  `getFuncOpsOrderedByCalls` (`:315-378`) collects `block.getOps<func::FuncOp>()`
  (`:326`) and walks `func::CallOp` (`:329`), asserting that each callee is
  a `func::FuncOp` (`:331`). The analyses (`:118-278`), `foldMemRefCasts`
  (`:431-467`), `analyzeModuleOp` (`:469-532`), `bufferizeModuleOp`
  (`:546-615`), whose "other ops" loop skips `func::FuncOp` (`:603`), and
  the no-analysis filter (`:631-639`) are typed the same way.
- `FuncAnalysisState` keys its five maps by `func::FuncOp`
  (`mlir/include/mlir/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.h:57-70`),
  and the queries the func models read it through are `static` in
  `FuncBufferizableOpInterfaceImpl.cpp` (`:66-160`), so another dialect's
  models can neither be keyed in it nor read it.
- `BufferizationOptions::FunctionArgTypeConverterFn` takes a `func::FuncOp`
  (`mlir/include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h:271-273`).
- `aliasingFuncOpBBArgsAnalysis` fails a function without a `func.return`
  (`OneShotModuleBufferize.cpp:139-145`), under a TODO that asks for an
  error on other `ReturnLike` ops.

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
  `OneShotModuleBufferize.cpp` is byte for byte the pin's.

## Patch

`llvm.patch` is the pull request, a `git diff` against 7208ba24. It relands
#110322 on the current driver, with its cause fixed:

- The driver's functions are the ops of the module that implement both
  `FunctionOpInterface` and `BufferizableOpInterface`
  (`isBufferizableFunction`). `transform.named_sequence` has no
  implementation, so it stays an "other op", as at the pin, and no test
  needs a payload tag. The calls are `CallOpInterface` ops; one whose
  callee is not a function of the driver orders nothing, where the pin
  asserted.
- `FuncAnalysisState`'s maps and `startFunctionAnalysis` are keyed by
  `FunctionOpInterface`; the queries the func models use are exported
  (`getFuncAnalysisState`, `getFuncOpAnalysisState`,
  `getEquivalentFuncArgIdx`, two `getCalledFunction`s,
  `getBufferizedFunctionArgType`), so another dialect's models read the
  analysis exactly as func's do. `getReturnOps` returns the `ReturnLike`
  terminators as `Operation *`.
- `FunctionArgTypeConverterFn` takes a `FunctionOpInterface`, the API
  change #110322 also made.
- `foldMemRefCasts` sets the type through `cloneTypeWith`; the
  no-analysis filter names a function by `SymbolTable::getSymbolName`.
- A function with no `ReturnLike` terminator is analyzed with no aliasing
  result, where the pin failed (the TODO goes).
- `BufferizationOptions::isOpAllowed` is unchanged; the func models keep
  their behaviour.

Tests: `one-shot-module-bufferize-function-interface.mlir` runs
`-test-one-shot-module-bufferize`, whose pass now attaches implementations
to the test dialect's function, call and return ops (written on the
exported queries): a callee written in place, a caller that passes its
buffer, a caller that reads after the call and gets a copy.
`one-shot-module-bufferize-transform-sequence.mlir` is the revert's case.
`one-shot-module-bufferize-no-return.mlir` is `no-return.mlir` with CHECK
lines. The existing `one-shot-module-bufferize*.mlir` files are unchanged.

The patch touches no file another carried patch touches, so it applies to
the pinned source alone and after the patches before it
(`tests/spec/upstream-patches`).

## Testing at the pin

Not built: no LLVM is built on the machine this was written on. The diff
applies to the pristine pin (`git apply --check`), and the four changed
`.cpp` files pass `-fsyntax-only` against the typecheck build's headers
of the pin, the test dialect's headers generated with its `mlir-tblgen`.
Stage 2 on each target, then the pull request's pre-merge CI, are the
first runs. `check-mlir` has not run with it.
`tests/upstream/one-shot-module-function-interface` checks the three
reproducers with the toolchain once stage 2 carries the patch.

## Upstreaming plan

Status: not filed; not built.

- Where: one pull request against llvm/llvm-project main, "[mlir][bufferization]
  Run One-Shot Module Bufferize on FunctionOpInterface", a reland of
  #110322. Its body names #110322 and #113124 by number and says what
  differs: the function set limited to function ops with an
  implementation, unresolved calls skipped, the exported queries, and the
  function that never returns. No issue.
- Upstream test: the three new files above.
- Before filing: search for a reland since 7208ba24 (if one landed, this
  patch goes and the pin takes it); check that the diff applies to
  then-current main and is clang-format clean; read the ArmSME integration
  tests (`mlir/test/Integration/Dialect/Linalg/CPU/ArmSME/`) for
  transform-driven bufferization, since they failed under #110322;
  `check-mlir` is the pull request's pre-merge CI's (upstream/README.md,
  **CI decides**). There is no `submission.md` yet.
- The patch goes when the pin's driver takes `FunctionOpInterface`; then
  this directory, its check and its `PINS.md` entry go, and the models of
  `idr.func`, `idr.call` and `idr.return` stay.
