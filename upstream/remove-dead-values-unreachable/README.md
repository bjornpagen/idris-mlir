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
that analysis finds unreachable. A value there has no liveness state and is
marked dead (`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp:233` for a
result, `:243` for a block argument: "has no liveness info, mark dead").

`processFuncOp` (`mlir/lib/Transforms/RemoveDeadValues.cpp:271`) then marks
a private function's arguments non-live when that state is missing
(`markLives` at `:292-293`, recorded at `:298`). The cleanup drops every
use (`:645`) and erases the arguments (`eraseArguments`, `:649`). The
operations that used them are not in the cleanup list, because the
analysis never looked at them either, so they keep null operands.

The cleanup drops uses the same way for a dead block argument
(`RemoveDeadValues.cpp:597`, then `eraseArgument`) and for a dead result
(`dropUsesAndEraseResults` at `:201`, the drop at `:207`, called from the
result cleanup at `:721`). A use in code the analysis never reached is left
null. That includes the result of a call whose callee's result goes, used
again from a call in that code.

## Patch

`llvm.patch` is the open pull request #208881, unchanged, plus the same
replacement at the two other drops. #208881 replaces each dead function
argument's remaining uses with `ub.poison` instead of calling
`dropAllUses`. The patch does that for a dead block argument and for a
dead result as well, through `createPoisonedValue`
(`RemoveDeadValues.cpp:521`), which is what the operand cleanup already
uses. It appends six modules to `mlir/test/Transforms/remove-dead-values.mlir`:

- `@unreachable_func_with_for_loops`, the test #208881 already has
- `@call_in_dead_region`, from `unreachable.mlir`
- `@uncalled`, from `uncalled.mlir`
- `@address_taken_callee`, the reproducer of
  `remove-dead-values-address-taken` (an extra test of the function-argument
  change, for this same pull request)
- `@dead_result_used_in_unreachable_code`, from `dead-result.mlir`
- `@dead_block_argument_used_in_unreachable_code`, from `dead-block-arg.mlir`

The patch does not yet leave an unchanged call as it is. The cleanup asks
`eraseOpResults` for every call of a private function that returns a value,
and `eraseOpResults` builds a new operation even when the set of results to
erase is empty (`dropUsesAndEraseResults`). The module prints the same and
the new call has a new address, so `OperationFingerPrint` changes. The next
toolchain build adds, at the start of `dropUsesAndEraseResults`, a return
when that set is empty. Until that build, `idr-dead-values` runs the pass
on a copy and keeps the module when the copy still hashes the same
(`foreign/idr/lib/Simplify/DeadValues.cppm`).

Built into the pinned toolchain, the test cases it adds pass with its
`mlir-opt`, under both prefixes, and it leaves the output of every other
case of the file as it was (the rest of the file uses the test dialect,
which the pinned build does not have, so FileCheck cannot run all of it).
`tests/upstream/remove-dead-values-unreachable` checks the reproducers in
this directory.

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

The patch is dropped when the pin includes #208881 and the same
`ub.poison` replacement for a dead block argument and a dead result. The
early return in `dropUsesAndEraseResults`, when the set to erase is empty,
is a later local change; `idr-dead-values` stops re-running the pass on a
copy once that return is in the toolchain.

## Upstreaming plan

Status: file upstream.

- Where: a review comment on the open pull request
  [#208881](https://github.com/llvm/llvm-project/pull/208881), and the same
  comment on
  [#206920](https://github.com/llvm/llvm-project/issues/206920) and
  [#203226](https://github.com/llvm/llvm-project/issues/203226). The text
  is `submission.md`. The block-argument and result parts are a follow-up
  pull request on top of #208881; its title and body are in that file too.
  `remove-dead-values-address-taken` is the extra test for #208881, not a
  second bug report.
- Upstream test: the six modules `llvm.patch` adds to
  `mlir/test/Transforms/remove-dead-values.mlir`. `@call_in_dead_region`,
  `@uncalled` and `@address_taken_callee` belong on #208881.
  `@dead_result_used_in_unreachable_code` and
  `@dead_block_argument_used_in_unreachable_code` belong on the follow-up.
- The patch is dropped when the pin includes #208881 and the `ub.poison`
  replacement for a dead block argument and a dead result.
