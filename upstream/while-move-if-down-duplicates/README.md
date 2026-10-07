# [mlir][scf] `WhileMoveIfDown` miscompiles a loop whose `scf.condition` forwards one `scf.if` result twice

At `llvmorg-23.1.2`, the `scf.while` canonicalization `WhileMoveIfDown`
rewrites the uses of an `scf.if` result in the `scf.condition` by replacing
*all* uses of that result with the if's else value. When the condition
forwards the same result at several positions, the first position rewrites
the others too: they no longer hold the if's result, the pattern's lookup no
longer finds them, and their after-region arguments keep receiving the else
value where the loop needs the then value.

## Reproduce

`twice.mlir`:

```mlir
func.func @main() -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c7 = arith.constant 7 : i32
  %r:2 = scf.while (%i = %c0) : (i32) -> (i32, i32) {
    %go = arith.cmpi slt, %i, %c1 : i32
    %v = scf.if %go -> i32 {
      scf.yield %c7 : i32
    } else {
      scf.yield %i : i32
    }
    scf.condition(%go) %v, %v : i32, i32
  } do {
  ^bb0(%a: i32, %b: i32):
    %s = arith.addi %a, %b : i32
    scf.yield %s : i32
  }
  return %r#0 : i32
}
```

```sh
mlir-opt --canonicalize twice.mlir
```

The loop runs once: both after-region arguments are 7, it yields 14, which
is not below 1, and `@main` returns 14. After `--canonicalize` the after
region is

```mlir
^bb0(%arg0: i32):
  %1 = arith.addi %arg0, %c7_i32 : i32
  scf.yield %1 : i32
```

`%a` became the then value 7, but `%b` stayed an argument, which the
condition now passes the else value `%i`, 0: the program returns 7.
Lowered with `--convert-scf-to-cf --convert-to-llvm
--reconcile-unrealized-casts`, translated and linked, the input exits with
14 and the canonicalized module with 7.

The duplicate need not be in the input. With `%x = arith.addi %v#1, %c0`
between the if and the condition and forwarded next to `%v#1`, the fold of
`%x` makes the two operands the same result in the middle of the run, and
the pattern, which the fold lets match, miscompiles the loop the same way:
the canonicalized loop never ends. It is safe only where
`RemoveDuplicateSuccessorInputUses` reaches the loop first.

## Cause

`mlir/lib/Dialect/SCF/IR/SCF.cpp:3464-3476`:

```cpp
for (auto [idx, arg] : llvm::enumerate(conditionOp.getArgs())) {
  auto it = llvm::find(ifOp->getResults(), arg);
  if (it != ifOp->getResults().end()) {
    size_t ifOpIdx = it.getIndex();
    Value thenValue = ifOp.thenYield()->getOperand(ifOpIdx);
    Value elseValue = ifOp.elseYield()->getOperand(ifOpIdx);

    rewriter.replaceAllUsesWith(ifOp->getResults()[ifOpIdx], elseValue);
    rewriter.replaceAllUsesWith(op.getAfterArguments()[idx], thenValue);
  }
}
```

`getArgs()` is read anew on each iteration, so after the first
`replaceAllUsesWith` of the if result the later operands hold `elseValue`
and are skipped.

## Proposed fix

Assign each condition operand that holds the if result on its own, so the
others still hold it when the loop reaches them:

```cpp
rewriter.replaceAllUsesWith(op.getAfterArguments()[idx], thenValue);
rewriter.modifyOpInPlace(conditionOp, [&] {
  conditionOp.getArgsMutable()[idx].assign(elseValue);
});
```

and add `twice.mlir`'s loop to `mlir/test/Dialect/SCF/canonicalize.mlir`.

## Status upstream

Fixed on main by a65eb8723 ("[mlir][scf] Fix WhileMoveIfDown with
duplicated scf.condition operands",
[#219458](https://github.com/llvm/llvm-project/pull/219458)), for
[#219456](https://github.com/llvm/llvm-project/issues/219456) (checked at
ed390ca4, October 2026): the pattern now assigns into the specific operand,
as above. It is not on `release/23.x`; the next release with it is 24.1.0,
and the workaround stays until the pin moves past that commit.

## Our workaround

None: the patch below is carried. The `canonicalize` steps of our pipeline
after `idr-tail-loops` run `WhileMoveIfDown` on the loops it makes, and
`idr-canonicalize` and the compile-time evaluator's lowering collect the
same patterns; before the patch, a canonicalization of the idr dialect had
the after region read a value its condition forwards twice through the
first argument only.

We have no Idris program that reaches the bug without that. The loop
`idr-tail-loops` makes for a function whose decision is a string or
`Integer` literal match ends in that match, an `scf.if` after lowering, and
a self call that passes one value as two arguments makes two of its results
yield the same values, which the region-branch patterns merge into one
result forwarded twice (`tests/programs/basic/string-loop-one-value-twice`).
In the runs we looked at, `ReplaceIfYieldWithConditionOrValue` makes the
loop's condition the if's before the results merge, and `WhileMoveIfDown`
takes the loop then, with every operand distinct. Whether it does depends
on the order in which the greedy driver visits the ops, not on anything a
pass of ours guarantees, so the fix belongs in the pattern.

## Patch

`llvm.patch` is main's a65eb8723 (#219458) as `git format-patch` wrote
it, unchanged; it applies to the pin as is.

## Upstreaming plan

Status: carried backport, not filed.

- Where: nothing to send. The patch is carried until the pin moves past
  a65eb8723 (24.1.0).
- Upstream test: the commit's own case in
  `mlir/test/Dialect/SCF/canonicalize.mlir`.
