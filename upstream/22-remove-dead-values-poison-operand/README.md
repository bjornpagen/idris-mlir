<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] `remove-dead-values` replaces a poison operand with a new poison

On llvm main at 7208ba24 (the pin), and at b43c0361 (main on 2026-10-15),
`--remove-dead-values` replaces every
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
a real change.) Found by this compiler's simplify round (the
`foreign/idr/lib/Simplify/Round.cppm` of the time, which the pipeline
cutover deleted), which ran the pass and `cse` in a fixed point:
the fixture `vectorize/rows-aarch64` (now `tests/vectorize-rows`) hit its round budget with 26 ops in
every round, an `idr.array.fold` whose result is dead feeding the same
poison back each time.

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

## Why there is no patch

There is no `llvm.patch`, and there is no `PINS.md` entry. The compiler
met this bug through one loop: the simplify rounds ran
`composite-fixed-point-pass`, whose fixpoint is an `OperationFingerPrint`,
and read the new poison as a change. The pipeline cutover of 2026-10-14
deleted the rounds; nothing in the tree runs a composite fixed point now,
and the dead values are removed once, after the optimizer, where a new
poison changes nothing a pass of ours reads. So nothing in the tree
reaches the bug, and the patch goes (AGENTS.md); the report stays a
submission, with the pull request as `pull-request.diff`, which this
repository does not apply.

## The fix

`pull-request.diff` is the pull request, a `git diff` against llvm main at
b43c0361 (2026-10-15), after #208881 (0edf6243), which changed another
step of the same cleanup. The first step keeps an operand defined by
`ub.poison`, and the seventh keeps a `ub.poison` that operands still use,
erasing it after the poison cleanup (step 8) only if its users are gone by
then. Every use left on such a poison is in a position the liveness
analysis found dead: the pass lists an op for erasure only when none of
its results is live. Test: a new file,
`mlir/test/Transforms/remove-dead-values-poison-operand.mlir`, the
reproducer under `composite-fixed-point-pass{max-iterations=2}` with
`-verify-diagnostics` (it fails on the non-convergence warning) and
FileCheck on the loop as it was. With `max-iterations=2` the pass runs a
second time only if the first changed the module, and warns only if the
second did too; without the change both runs replace the two operands,
so the test warns.

## Testing

On 2026-10-15: `pull-request.diff` applies with no offset to llvm main at
b43c0361 and to the pin (7208ba24, where its second and third hunks sit 11
lines earlier, before #208881). The patched `RemoveDeadValues.cpp` of main
passes `-fsyntax-only` with the typecheck build's command for that unit.
The new test's name is free on main.

Not run: no `mlir-opt` with the change has been built, so the new test has
not been seen to pass with it or fail without it, and `check-mlir` has not
run. What it should print is read from the code: `processRegionBranchOp`
marks the loop's init operand and its yield's operand dead (both are
forwarded only to the dead iteration argument and result) for replacement
by poison, whatever `canonicalize` is, and lists `%p` for erasure.

## Upstreaming plan

Status: ready to file, not filed; not carried. `submission.md` has the
issue, the pull request title and body and the checklist to run before
posting. No issue or pull request covers it: searched llvm/llvm-project
for remove-dead-values and poison, and RemoveDeadValues, 2026-10-15. The
open remove-dead-values reports and pull requests (#231868, #231846,
#216652, #182711, #208742, #208940) are about other steps: the pull
requests change how branch operands and block arguments are cleaned, not
the region-branch operands or the operation cleanup this changes. If one
of them lands first, the diff may need a textual rebase (#182711
renumbers the cleanup's steps).

- Where: an issue (the reproducer, the composite pass's error) and a pull
  request against main, one commit, this diff. `check-mlir` is the pull
  request's pre-merge CI's (upstream/README.md, **CI decides**).
- Upstream test: `mlir/test/Transforms/remove-dead-values-poison-operand.mlir`.
- Touches `RemoveDeadValues.cpp`, as 06 does, in other hunks; independent
  of 16.
- When it goes: when the pin has the fix.
