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

`llvm.patch` is the open pull request #208881, unchanged, plus a follow-up
on top of it.

Pull request #208881 replaces the remaining uses of each dead function
argument with `ub.poison` instead of calling `dropAllUses`, and adds
`@unreachable_func_with_for_loops` (#206920).

The follow-up makes that the only way the pass retires a value: one helper,
`replaceUsesWithPoison`, puts a `ub.poison` at the value's definition (the
start of the block for an argument, before the op for a result) and
replaces every use with it, and does nothing for an unused value. The
function-argument cleanup, the block-argument cleanup, the result cleanup
(`dropUsesAndEraseResults`, renamed `poisonUsesAndEraseResults`) and the
erasure of whole ops all call it; `createPoisonedValue` moves up so the
helper can use it, and the pass has no `dropAllUses` left. Poison that ends
up unused is already removed at the end of the cleanup.

Tests appended to `mlir/test/Transforms/remove-dead-values.mlir`, each with
the same `CHECK` and `CHECK-CANONICALIZE` lines:

- `@unreachable_func_with_for_loops`, #208881's own;
- `@call_in_dead_region`, from `unreachable.mlir` (a call left in a
  function only a dead region calls); fixed by #208881;
- `@address_taken_callee`, the module of
  `remove-dead-values-address-taken`, exactly as that directory posts it;
  fixed by #208881;
- `@dead_result_used_in_unreachable_code`, from `dead-result.mlir`; fixed
  by the follow-up;
- `@dead_block_argument_used_in_unreachable_code`, from
  `dead-block-arg.mlir`; fixed by the follow-up.

`uncalled.mlir` is the case #208881's own test already covers, so it has no
module of its own upstream; `tests/upstream/remove-dead-values-unreachable`
still checks it.

Checked against llvmorg-23.1.2 with `mlir-opt` binaries linked from the
pinned libraries plus the patched `RemoveDeadValues.cpp`: each new module
passes FileCheck under both prefixes with the full patch; with #208881
alone the first three pass and the last two fail with `null operand found`;
the pinned `mlir-opt` fails all five. Every module that was already in the
file produces byte-identical output with and without the patch (the ones
using the test dialect cannot be parsed by that build, under either). The
changed lines are clang-formatted.

The patch still rebuilds a call whose result set to erase is empty: the
cleanup lists every call of a private function that returns a value, and
`eraseOpResults` builds a new op even for an empty set. The module prints
the same, but `OperationFingerPrint` changes, so `idr-dead-values` runs the
pass on a copy and keeps the module when the copy still hashes the same
(`foreign/idr/lib/Simplify/DeadValues.cppm`). That is a separate change,
not in this patch.

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

The patch is dropped when the pin includes #208881 and the follow-up.
`idr-dead-values` keeps running the pass on a copy until `remove-dead-values`
leaves a call with nothing to erase as it is.

## Upstreaming plan

Status: file upstream.

- Where: a comment on the open pull request
  [#208881](https://github.com/llvm/llvm-project/pull/208881), and a short
  one on [#206920](https://github.com/llvm/llvm-project/issues/206920) and
  [#203226](https://github.com/llvm/llvm-project/issues/203226); then a
  follow-up pull request stacked on #208881 for block arguments and
  results. No new issue. The texts are in `submission.md`.
  `@address_taken_callee` is posted by `remove-dead-values-address-taken`,
  not from here.
- Upstream test: `@call_in_dead_region` offered to #208881;
  `@dead_result_used_in_unreachable_code` and
  `@dead_block_argument_used_in_unreachable_code` in the follow-up.
- The patch is dropped when the pin includes #208881 and the follow-up.
