# [mlir] `remove-dead-values` erases the arguments of an unreachable function but keeps their uses

At `llvmorg-23.1.2`, `--remove-dead-values` leaves operations with null
operands (a verifier failure, or an assertion in `matchPattern` from the
region-branch canonicalization that the pass runs afterwards) when a
private function is never reached, because nothing calls it or because its
only call is in a region that constant propagation rules out.

## Reproduce

`unreachable.mlir` (the call of `@g` is under a false `scf.if`):

```mlir
func.func private @ext(i32)

func.func private @g(%x: i32) {
  func.call @ext(%x) : (i32) -> ()
  return
}

func.func @main(%v: i32) {
  %false = arith.constant false
  scf.if %false {
    func.call @g(%v) : (i32) -> ()
  }
  return
}
```

`uncalled.mlir` is the same without `@main`: nothing calls `@g`.

```
$ mlir-opt unreachable.mlir --remove-dead-values
unreachable.mlir:4:3: error: null operand found
  func.call @ext(%x) : (i32) -> ()
  ^
note: see current operation: "func.call"(<<NULL VALUE>>) <{callee = @ext}> : (<<NULL TYPE>>) -> ()
```

`mlir-opt` exits 1. `uncalled.mlir` fails the same way. In a larger module,
where a region op keeps the orphaned use, the pass instead asserts in
`matchPattern` (`mlir/include/mlir/IR/Matchers.h:491`) during its final
region-branch canonicalization, or crashes.

Expected: the module is left valid. Either the unreachable function is left
alone, or its body is deleted with its arguments.

## Cause

`RunLivenessAnalysis` runs with dead-code analysis, so it never visits the
body of a function that dead-code analysis finds unreachable: its arguments
have no liveness state and count as dead (`LivenessAnalysis.cpp`, "has no
liveness info, mark dead"). `processFuncOp`
(`mlir/lib/Transforms/RemoveDeadValues.cpp:271`) then marks them non-live,
and the cleanup drops all their uses and erases them
(`RemoveDeadValues.cpp:644-649`). The operations that used them are not in
the cleanup list, because the analysis never looked at them either, so they
keep null operands.

## Proposed fix

In `processFuncOp`, skip a function whose entry block the solver did not
find executable (`solver.lookupState<dataflow::Executable>(
solver.getProgramPointBefore(&entry))`), as the pass already skips public
and external functions; or erase such a function's body along with its
arguments. The same check belongs wherever the pass treats a value without
liveness state as dead: a value is only dead if the analysis reached its
uses.

## Our workaround

`PINS.md`: `prune-before-remove-dead-values`. `idr-prune`
(`foreign/idr/lib/Passes/Prune.cc`) runs the same analyses before
`remove-dead-values` and empties every block they prove unreachable, and
`symbol-dce` then removes the functions that only that code referred to.
