# [mlir] `remove-dead-values` replaces a poison operand with a new poison

On llvm main at 7208ba24 (the pin), `--remove-dead-values` replaces every
operand it finds dead, of a region branch op or its terminator, with a new
`ub.poison`, also when the operand already is one. The module prints the
same, but the poison is a new operation, so `OperationFingerPrint`
changes: `composite-fixed-point-pass` over the pass never sees a run that
changes nothing on such a module, and with `cse` after it (which merges the
new poison back) the pair cycles for ever.

## Reproduce

`poison-operand.mlir` (a loop whose result is dead and whose iteration
value is already poison; the store keeps the loop):

```mlir
func.func @f(%lb: index, %ub: index, %step: index, %m: memref<i64>) {
  %p = ub.poison : i64
  %r = scf.for %i = %lb to %ub step %step iter_args(%a = %p) -> (i64) {
    %c = arith.constant 1 : i64
    memref.store %c, %m[] : memref<i64>
    scf.yield %p : i64
  }
  return
}
```

`mlir-opt poison-operand.mlir --remove-dead-values='canonicalize=false'
--cse` prints what `mlir-opt poison-operand.mlir` prints, yet:

```
$ mlir-opt poison-operand.mlir --composite-fixed-point-pass='pipeline=remove-dead-values{canonicalize=false} max-iterations=1 on-convergence-failure=error'
poison-operand.mlir:1:1: error: Composite pass "CompositeFixedPointPass"+ didn't converge in 1 iterations
```

(With the pass's canonicalization the loop loses its dead iteration value,
a real change.) `tests/upstream/remove-dead-values-poison-operand` checks
the reproducer. Found by this compiler's simplify round
(`foreign/idr/lib/Simplify/Round.cppm`), which runs the pass and `cse` in a
fixed point: `tests/idr/vectorize/rows-aarch64` hit its round budget with
26 ops in every round, an `idr.array.fold` whose result is dead feeding
the same poison back each time.

## Expected

A run of the pass that has nothing to replace leaves every operation as it
is, so the composite pass stops after one run.

## Cause

Two steps of the cleanup each put a new `ub.poison` where one already is:

- `processRegionBranchOp` marks an operand dead when every successor input
  it is forwarded to is dead, whatever value it is, and the cleanup's first
  step sets each marked operand to `createPoisonedValue`, a new `ub.poison`
  for any operand with uses.
- The liveness analysis finds the `ub.poison` itself dead (its value only
  reaches dead inputs), so the pass schedules it for erasure, and the
  cleanup's seventh step replaces the remaining uses of an op it erases
  with a new `ub.poison` before erasing it.

## Patch

`llvm.patch` is the pull request, a `git diff` against 7208ba24, the pin.
The first step keeps an operand defined by `ub.poison`, and the seventh
keeps a `ub.poison` that operands still use, erasing it after the poison
cleanup (step 8) only if its users are gone by then. Test: a new file,
`mlir/test/Transforms/remove-dead-values-poison-operand.mlir`, the
reproducer under `composite-fixed-point-pass{max-iterations=2}` with
`-verify-diagnostics` (it fails on the non-convergence warning) and
FileCheck on the loop as it was. It applies to the pinned source alone and
after the other patches (06 and 16 touch the same file, other hunks).

## Upstreaming plan

Status: not filed; carried as `llvm.patch`.

- Where: an issue (the reproducer, the composite pass's error) and a pull
  request against main, one commit, this patch.
- Before filing: the patch applied to then-current main, `check-mlir` left
  to LLVM's pre-merge CI; search the tracker for remove-dead-values and
  fixed points (06's #208881 is near).
- When it goes: when the pin has the fix; then this report, the PINS.md
  entry `remove-dead-values-poison-operand` and its check go.
