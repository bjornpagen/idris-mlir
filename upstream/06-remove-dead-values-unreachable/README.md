# [mlir] `remove-dead-values` leaves a null operand in code liveness never visits

In MLIR at `llvmorg-23.1.2`, `--remove-dead-values` erases a value the
liveness analysis marks dead and drops its uses first. A use in code that
analysis never visits stays in the module with a null operand. `mlir-opt`
then reports `null operand found`, or asserts in `matchPattern`
(`mlir/include/mlir/IR/Matchers.h:491`) during the region-branch
canonicalization the pass runs afterwards
(`mlir/lib/Transforms/RemoveDeadValues.cpp:833`).

The value is a dead function argument (a private function nothing live
calls, or whose only call is in a region a constant rules out), a dead
block argument used only in such a region, or a dead result used only
there.

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
`matchPattern` during its final region-branch canonicalization, or crashes.

`dead-result.mlir`: the result of `@f` is unused at the call `@main` makes,
and used after a second call under a condition only the interprocedural
analysis knows is false (a call of `@never`, which returns `false`).
`dead-block-arg.mlir` is the same for a block argument whose one use is
under that condition.

```
$ mlir-opt dead-result.mlir --remove-dead-values
dead-result.mlir:18:5: error: null operand found
    func.call @ext(%s) : (i32) -> ()
$ mlir-opt dead-block-arg.mlir --remove-dead-values
dead-block-arg.mlir:13:5: error: null operand found
    func.call @ext(%a) : (i32) -> ()
```

## Expected

The module is left valid. An operation the pass does not delete keeps an
operand: `ub.poison` of the erased value's type, which is what the pass
already uses for a result of an operation it deletes.

## Cause

`RunLivenessAnalysis` runs with dead-code analysis, so it never visits code
that analysis finds unreachable. Since #153973 it then gives every value
there a state that says dead
(`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp:233` for a result, `:243`
for a block argument).

The pass walks every op, unreachable or not, and erases most of what uses a
dead value: a simple op with a dead operand goes (`processSimpleOp`,
`RemoveDeadValues.cpp:230`), and its results' uses take `ub.poison` when it
is erased (`:745-755`). Two kinds of op stay: a call (the walk skips every
`CallOpInterface` op, `:807`, and its operands change only when its callee's
arguments go) and a region branch op with side effects whose dead operand
is not forwarded to a region (the bounds of `scf.for`, `affine.for`).

Three cleanups drop the uses of the value they erase instead of poisoning
them: a dead function argument (`:645`, before `eraseArguments` at `:649`),
a dead block argument (`:597`, before `eraseArgument`), and a dead result
(`dropUsesAndEraseResults`, `:201`, the drop at `:207`, called at `:721`). A
use by one of the ops above is left null. The three ways in:

- a private function nothing live calls, or whose only call is in a region
  a constant rules out: all its arguments are dead (`processFuncOp`,
  `:271`, `markLives` at `:292`);
- a block argument whose only use is in such a region;
- a callee result dead at every call the analysis visits: `processFuncOp`
  erases it from every call (`:360-363`), including a call in such a region
  whose result is used there.

## Patch

`llvm.patch` is the pull request, against llvm main at 7208ba24, the
pin. It changes `RemoveDeadValues.cpp`: one helper,
`replaceUsesWithPoison`, replaces the uses of a value about to be erased
with a `ub.poison` at its definition (the start of the block for an
argument, before the op for a result) and does nothing for an unused
value. The function-argument cleanup, the block-argument cleanup, the
result cleanup (`dropUsesAndEraseResults`, renamed
`poisonUsesAndEraseResults`) and the erasure of whole ops all call it, and
the pass drops no use any more. Poison that ends up unused is already
removed at the end of the cleanup.

It appends to `mlir/test/Transforms/remove-dead-values.mlir`, with
`CHECK` and `CHECK-CANONICALIZE` lines that check the property (the kept
call takes a `ub.poison` of the type), not the order:

- `@dead_function_argument_used_in_unreachable_code`, from
  `unreachable.mlir`;
- `@dead_result_used_in_unreachable_code`, from `dead-result.mlir`;
- `@dead_block_argument_used_in_unreachable_code`, from
  `dead-block-arg.mlir`.

While the pin was llvmorg-23.1.2, `llvm.patch` was a version for it
whose test hunk also carried two modules that are not part of the pull
request: `@unreachable_func_with_for_loops`, the test of the open pull
request #208881 (the same fix for function arguments alone), and
`@address_taken_callee`, as `remove-dead-values-address-taken` posts it.
Neither is carried now. `uncalled.mlir` is the case #208881's test
covers; `tests/upstream/remove-dead-values-unreachable` checks all four
reproducers, and `tests/upstream/remove-dead-values-address-taken` the
address-taken one.

Checked against llvmorg-23.1.2, with that version, in an `mlir-opt`
linked from its libraries plus the patched `RemoveDeadValues.cpp`. Each
of the five appended modules passes FileCheck under both prefixes. With
#208881 alone the first three pass and the dead-result and
dead-block-argument modules fail with `null operand found`. The
unpatched 23.1.2 `mlir-opt` fails all five.
Every module already in the file gives byte-identical output with and
without the patch (the two that use the test dialect fail to parse in
this build either way). The changed lines are clang-format clean under
trunk's `.clang-format`. On main, see Testing on main.

The patch still rebuilds a call whose set of results to erase is empty:
the cleanup lists every call of a private function that returns a value,
and `eraseOpResults` builds a new op even for an empty set. The module
prints the same, but `OperationFingerPrint` changes, so `idr-dead-values`
runs the pass on a copy and keeps the module when the copy still hashes
the same (`foreign/idr/lib/Simplify/DeadValues.cppm`). That is a separate
matter and not part of this patch.

## Workaround

The patch above is what runs. Before it, `idr-prune` ran the same analyses
before `remove-dead-values` and emptied every block they prove unreachable,
and `symbol-dce` then removed the functions that only that code referred
to. With the patch, the simplify round without them gave k-nucleotide and
every-types-export the same objects, byte for byte, in as many rounds, so
both went. What emptying did beyond the bug (a region a constant rules out
ended in `ub.unreachable`, so that a match whose taken region crashes was
seen never to complete) the match canonicalization now decides from the
region the constant selects.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

Then, with this patch's `RemoveDeadValues.cpp` change alone reverted:
`Transforms/remove-dead-values.mlir` fails; with
the change back, it passes.

## Upstreaming plan

Status: file upstream.

- Where: a new issue (the block-argument and result cases; #206920 and
  #203226 cover function arguments), a pull request against llvm main
  (`llvm.patch`), and a short comment on the open pull request
  [#208881](https://github.com/llvm/llvm-project/pull/208881), which
  fixes function arguments alone and has been approved but not merged
  since 2026-07-18. A review suggestion on #208881 would reopen an
  approved review, and a pull request stacked on someone else's branch
  needs a user branch Bjorn cannot push, so the pull request stands on
  trunk; whichever of the two lands second rebases. The texts and the
  overlap with #208940 and #182711 are in `submission.md`.
- Upstream test: the three modules listed under Patch.
- The patch is dropped when the pin includes the pull request (or
  #208881 together with a fix for block arguments and results).
