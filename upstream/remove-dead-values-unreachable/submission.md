# Submission

Status: file. Review comments, and a follow-up, on the open pull request
https://github.com/llvm/llvm-project/pull/208881, and the same comment on
https://github.com/llvm/llvm-project/issues/206920 and
https://github.com/llvm/llvm-project/issues/203226. Paste the comment
below on all three. The follow-up is a new pull request for the
block-argument and result parts; #208881 changes only the function-argument
drop. There is no new issue.

Author the commit as Bjorn, as an individual. This work was done outside
any employer. Do not name an employer. Do not add an Assisted-by trailer.
Do not add Contributed-by lines in the source. Do not @mention anyone.

LLVM reviews this on GitHub pull requests. Phabricator is read-only. Not
Bugzilla. Each pull request is one self-contained commit. Squash and merge,
so the pull request title and body become the commit.

`remove-dead-values-address-taken` is the extra test for #208881, not a
second bug report. Its reproducer is the `@address_taken_callee` module in
`llvm.patch` and in the comment below. Do not file an issue from that
directory.

## Comment

Paste the following on https://github.com/llvm/llvm-project/pull/208881,
https://github.com/llvm/llvm-project/issues/206920 and
https://github.com/llvm/llvm-project/issues/203226.

----- paste -----

`--remove-dead-values` drops the uses of a value it is about to erase. Liveness never visits code that dead-code analysis has ruled out, and a value with no liveness state is marked dead (`mlir/lib/Analysis/DataFlow/LivenessAnalysis.cpp:233` for a result, `:243` for a block argument). An operation in that code is not on the cleanup list, so after the drop it keeps a null operand. On llvmorg-23.1.2, `mlir-opt --remove-dead-values` then reports `null operand found`, or asserts in `matchPattern` (`mlir/include/mlir/IR/Matchers.h:491`) from the region-branch canonicalization at the end of the pass (`mlir/lib/Transforms/RemoveDeadValues.cpp:833`).

https://github.com/llvm/llvm-project/pull/208881 replaces the remaining uses of a dead function argument with `ub.poison` before erasing it (`RemoveDeadValues.cpp:645`). That fixes the unreachable private function in https://github.com/llvm/llvm-project/issues/206920 and https://github.com/llvm/llvm-project/issues/203226. The pass already gives `ub.poison` to a use of a result of an operation it deletes, and a side-effecting operation in unreachable code has to stay, so poison is the right replacement there.

The cleanup still drops uses in two other places, which that pull request does not change:

- a dead block argument (`RemoveDeadValues.cpp:597`, then `eraseArgument`)
- a dead result (`dropUsesAndEraseResults` at `RemoveDeadValues.cpp:201`, the drop at `:207`, called from the result cleanup at `:721`)

A follow-up on top of #208881 gives those uses `ub.poison` as well.

Tests for `mlir/test/Transforms/remove-dead-values.mlir`, beside `@unreachable_func_with_for_loops`, which is already on #208881. Each exits 1 with `null operand found` at llvmorg-23.1.2. After the poison replacement, the surviving call takes `ub.poison`.

`@call_in_dead_region`. The only call of `@g` is under `scf.if` of a false constant, so liveness never enters `@g` and its argument is dead. This is the function-argument fix on #208881.

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

`@uncalled`. Nothing calls `@g`. Same function-argument fix.

```mlir
func.func private @ext(i32)

func.func private @g(%x: i32) {
  func.call @ext(%x) : (i32) -> ()
  return
}
```

`@address_taken_callee`. Another test of that same function-argument change, not a separate bug. `@ignores` is named by `func.constant`, so the pass leaves its signature alone, and it never reads its parameter. The argument `@caller` passes is dead, and `func.call @ignores` is left with a null operand. `ub.poison` for that argument keeps the call.

```mlir
func.func private @ignores(%x: i64) -> i64 {
  %c = arith.constant 7 : i64
  return %c : i64
}

func.func private @caller(%a: i64, %b: i64) -> i64 {
  %t = func.call @ignores(%b) : (i64) -> i64
  %u = arith.addi %a, %t : i64
  return %u : i64
}

func.func @main(%a: i64) -> i64 {
  %f = func.constant @ignores : (i64) -> i64
  %r = func.call_indirect %f(%a) : (i64) -> i64
  %t = func.call @caller(%r, %a) : (i64, i64) -> i64
  return %t : i64
}
```

`@dead_block_argument_used_in_unreachable_code`. `%a` is used only under `scf.if` of a call of `@never`, which returns false. Liveness marks `%a` dead, and `RemoveDeadValues.cpp:597` still drops that use. #208881 does not change this line. The follow-up does. On llvmorg-23.1.2 the error is `null operand found` at `func.call @ext(%a)`.

```mlir
func.func private @ext(i32)

func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}

func.func @main(%v: i32) {
  %no = func.call @never() : () -> i1
  cf.br ^bb1(%v : i32)
^bb1(%a: i32):
  scf.if %no {
    func.call @ext(%a) : (i32) -> ()
  }
  return
}
```

`@dead_result_used_in_unreachable_code`. The result of `@f` is dead at the call liveness visits, so that result is removed, and the call of `@f` under the false condition keeps a null operand (`dropUsesAndEraseResults`). #208881 does not change this. The follow-up does. On llvmorg-23.1.2 the error is `null operand found` at `func.call @ext(%s)`.

```mlir
func.func private @ext(i32)

func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}

func.func private @f() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}

func.func @main() {
  %r = func.call @f() : () -> i32
  %no = func.call @never() : () -> i1
  scf.if %no {
    %s = func.call @f() : () -> i32
    func.call @ext(%s) : (i32) -> ()
  }
  return
}
```

The FileCheck modules for these five, plus `@unreachable_func_with_for_loops`, are the tests appended to `mlir/test/Transforms/remove-dead-values.mlir` in the patch carried against llvmorg-23.1.2. `@call_in_dead_region`, `@uncalled` and `@address_taken_callee` belong on #208881. `@dead_block_argument_used_in_unreachable_code` and `@dead_result_used_in_unreachable_code` belong on the follow-up.

----- end -----

## Follow-up pull request

One commit, based on the branch of #208881. The commit is the two remaining
drops and their two tests
(`@dead_block_argument_used_in_unreachable_code`,
`@dead_result_used_in_unreachable_code`). The function-argument change, and
`@unreachable_func_with_for_loops`, `@call_in_dead_region`, `@uncalled` and
`@address_taken_callee`, stay on #208881. Squash and merge: the title below
is the pull request title, and the body is the pull request body. Together,
with a blank line between them, they are the commit. The body already names
#208881, so leave that text as it is.

### Title

```
[mlir] Poison remaining uses of dead block arguments and results
```

### Body

```
remove-dead-values drops every use of a value it erases. Liveness never
visits code that dead-code analysis has ruled out, and a value with no
liveness state is marked dead, so a use in that code is left null. The
module then fails verification ("null operand found"), or the pass
asserts in matchPattern while canonicalizing region-branch operations.

#208881 replaces the remaining uses of a dead function argument with
ub.poison, which is what the pass already does for a result of an
operation it deletes. Two other drops still leave a null operand.

A dead block argument is dropped before eraseArgument. A block argument
whose only use is in a region the analysis does not visit (an scf.if
whose condition is a call of a function that returns false) keeps that
use as a null operand.

A dead result is dropped in dropUsesAndEraseResults, before
eraseOpResults. The result of a call is removed because the callee's
result is dead at every call the analysis visits, and another call of
that function, in code the analysis skipped, still uses it.

Replace those uses with ub.poison before the value goes, so an operation
the pass does not delete stays valid. Tests:
@dead_block_argument_used_in_unreachable_code and
@dead_result_used_in_unreachable_code in
mlir/test/Transforms/remove-dead-values.mlir.
```
