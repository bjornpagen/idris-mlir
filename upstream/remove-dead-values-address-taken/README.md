# [mlir] `remove-dead-values` erases a caller's argument that is passed to an address-taken function, and leaves the call with a null operand

At `llvmorg-23.1.2`, `--remove-dead-values` leaves a `func.call` with a
null operand when a private function's argument is dead only because it is
passed to a function that is also referenced other than by calls (by
`func.constant`, say) and never reads that parameter.

## Reproduce

`address-taken.mlir`:

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

```
$ mlir-opt address-taken.mlir --remove-dead-values
address-taken.mlir:7:8: error: null operand found
  %t = func.call @ignores(%b) : (i64) -> i64
       ^
note: see current operation: %0 = "func.call"(<<NULL VALUE>>) <{callee = @ignores}> : (<<NULL TYPE>>) -> i64
```

`mlir-opt` exits 1. When the value passed is an op's result instead of a
block argument (`%s = arith.addi %a, %a` in `@main`, passed to `@ignores`),
the pass replaces it with `ub.poison` and the module stays valid.

Expected: the module is left valid, with `ub.poison` passed for the dead
argument, as it is for a dead op result.

## Cause

`processFuncOp` (`mlir/lib/Transforms/RemoveDeadValues.cpp:284-289`)
skips `@ignores`, because a non-call operation uses its symbol: its
signature must stay, so the calls of it keep all their operands, and no
cleanup entry is made for them. Liveness still finds `%b` dead, since
`@ignores` never reads its parameter, so `processFuncOp` for `@caller`
marks `%b` non-live, and the cleanup drops all its uses before erasing it
(`RemoveDeadValues.cpp:643-649`). The call of `@ignores` is one of those
uses, and nothing removes or replaces that operand.

## Proposed fix

When the cleanup erases a dead block argument, replace its remaining uses
with `ub.poison` (as the pass already does for dead op results) instead of
dropping them; or have liveness treat the arguments of a call whose callee
`processFuncOp` skips as live.

## Status upstream

Not filed. [llvm/llvm-project#208881](https://github.com/llvm/llvm-project/pull/208881)
replaces the remaining uses of a dead function argument with `ub.poison`
instead of dropping them, which fixes this call. It is open for the
unreachable-function reports
[#206920](https://github.com/llvm/llvm-project/issues/206920) and
[#203226](https://github.com/llvm/llvm-project/issues/203226),
and it is not merged (checked at main ed390ca4, October 2026). The
address-taken call is a comment and a test on that pull request.

## Our workaround

None in this directory. `remove-dead-values-unreachable/llvm.patch` is the
carried fix, and the call passes `ub.poison` for such a parameter. That
patch still builds a new call when it erases no result: `eraseOpResults`
builds a new operation even when the set of results to erase is empty.
The next toolchain build adds an early return to
`dropUsesAndEraseResults` when that set is empty. Until that build,
`idr-dead-values` runs the pass on a copy and keeps the module when the
copy still hashes the same
(`foreign/idr/lib/Simplify/DeadValues.cppm`). Before the patch,
`idr-prune` made each call of such a function pass `ub.poison` for every
parameter the function never reads, right before `remove-dead-values`.

## Why there is no patch

This directory has no patch. The fix is
`remove-dead-values-unreachable/llvm.patch`, the argument change from
[#208881](https://github.com/llvm/llvm-project/pull/208881): replacing a
dead argument's remaining uses with `ub.poison` covers a call of an
address-taken function the same way it covers unreachable code. That
patch adds module `@address_taken_callee` to
`mlir/test/Transforms/remove-dead-values.mlir`. A second patch appending
to that test file would not apply after the first.

## Upstreaming plan

Status: file as a comment and a test on
https://github.com/llvm/llvm-project/pull/208881. No new issue. No second
pull request. Not Bugzilla. Author is Bjorn, individual, work done outside
any employer. No Assisted-by. No @mentions.

- Where: one comment on that pull request. The text to paste is
  `submission.md` in this directory.
- Upstream test: module `@address_taken_callee` below, for
  `mlir/test/Transforms/remove-dead-values.mlir`. The body is
  `address-taken.mlir`. `@caller` passes `ub.poison : i64` to `@ignores`.
  `remove-dead-values-unreachable/llvm.patch` adds this same module.

```mlir
// @ignores keeps its signature, since a func.constant names it, and never
// reads its parameter, so the value @caller passes it is dead: the call
// keeps its operand, which becomes poison.
// CHECK-LABEL: module @address_taken_callee
// CHECK:         func.func private @caller(
// CHECK:           %[[P:.*]] = ub.poison : i64
// CHECK:           call @ignores(%[[P]])
// CHECK-CANONICALIZE-LABEL: module @address_taken_callee
// CHECK-CANONICALIZE:         call @ignores(
module @address_taken_callee {
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
}
```
