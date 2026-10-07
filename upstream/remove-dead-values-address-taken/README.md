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

Not filed yet. The open pull request
[#208881](https://github.com/llvm/llvm-project/pull/208881), written for
`remove-dead-values-unreachable`'s issues, would fix this case too; it is
not merged (checked at main ed390ca4, October 2026). Add
`address-taken.mlir` to that pull request as a test rather than filing an
issue of its own.

## Our workaround

None: `remove-dead-values-unreachable`'s patch is carried, and the call
passes `ub.poison` for such a parameter itself. Before the patch,
`idr-prune` made each call of such a function pass `ub.poison` for every
parameter the function never reads, right before `remove-dead-values`.

## Why there is no patch

The fix is `remove-dead-values-unreachable`'s patch (#208881): replacing a
dead argument's remaining uses with `ub.poison` covers a call of an
address-taken function as it covers unreachable code, and that patch adds
`address-taken.mlir` to the upstream test. Two patches appending to the
same test file would not apply one after the other.

## Upstreaming plan

- Where: a comment on #208881 with `address-taken.mlir`, asking for it as
  a test; no issue of its own.
- Upstream test: the `@address_taken_callee` module in
  `remove-dead-values-unreachable/llvm.patch`.
- Status: not sent. Goes with `remove-dead-values-unreachable`.
