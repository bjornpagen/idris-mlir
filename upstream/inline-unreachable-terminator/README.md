# [mlir] Inlining a callee whose body ends in `ub.unreachable` aborts

At `llvmorg-23.1.2`, `--inline` aborts when it inlines a single-block
callee whose terminator is `ub.unreachable` (a function that never returns:
it traps, or its body is proved impossible).

## Reproduce

`never.mlir`:

```mlir
func.func private @never() -> i32 {
  ub.unreachable
}

func.func @main() -> i32 {
  %0 = func.call @never() : () -> i32
  return %0 : i32
}
```

```
$ mlir-opt never.mlir --inline
must implement handleTerminator in the case of one inlined block
UNREACHABLE executed at .../mlir/Transforms/DialectInlinerInterface.h.inc:82!
```

`mlir-opt` aborts (exit status 134). Expected: `@main` becomes
`ub.unreachable` (or keeps the call).

## Cause

`UBInlinerInterface` (`mlir/lib/Dialect/UB/IR/UBOps.cpp:25-32`) makes every
`ub` op legal to inline but implements neither `handleTerminator` hook, and
`inlineRegionImpl` (`mlir/lib/Transforms/Utils/InliningUtils.cpp:330-340`)
takes the single-block fast path for any single-block callee: it asks the
terminator's dialect to replace the call's results with the terminator's
operands, then erases the terminator and splices the rest of the caller's
block after the inlined operations. `ub.unreachable` has no operands to
forward, and nothing may follow it in its block, so the default hook
(`DialectInlinerInterface.td:103-107`) is `llvm_unreachable`. The
multi-block path would call the other default hook (`:86-89`), which is
`llvm_unreachable` too.

## Proposed fix

Two parts:

1. `inlineRegionImpl` takes the single-block fast path only when the
   inlined block's terminator is return-like
   (`hasTrait<OpTrait::ReturnLike>()`); otherwise it inlines as multi-block,
   splitting the caller's block at the call.
2. `UBInlinerInterface` implements `handleTerminator(Operation *, Block *)`
   as a no-op: `ub.unreachable` stays the terminator of its inlined block,
   and the block after the call becomes unreachable, which later cleanups
   remove.

## Status upstream

Not filed yet. The open issue
[#206083](https://github.com/llvm/llvm-project/issues/206083) is the same
family, with `vector.yield` as the terminator the inliner cannot handle; its
pull request [#206218](https://github.com/llvm/llvm-project/pull/206218)
fixes the vector dialect only, so `ub.unreachable` still aborts (checked at
main ed390ca4, October 2026). File this one citing #206083, or ask there
for part 1 of the fix, which covers both.

## Our workaround

`PINS.md`: `inline-unreachable`. No function body the compiler writes ends
in `ub.unreachable`: `Emit` (`epilogue` in
`compiler/src/IdrisMLIR/Emit/Bodies.idr`), `idr-prune` and `idr-tail-loops`
end a body that never returns with `ub.poison` and `func.return`, which is
never reached, and the program's verifier refuses a body that ends in
`ub.unreachable`. `ub.unreachable` appears only at the end of match
regions, which the inliner does not see as callees.

## Patch

`llvm.patch` implements both parts of the proposed fix: the single-block
fast path only for a `ReturnLike` terminator, the inliner pass treating
such a callee as multi-block for a caller region that must stay one
block, and `UBInlinerInterface::handleTerminator(Operation *, Block *)`
as a no-op. Tests in `mlir/test/Dialect/UB/inlining.mlir`. Drafted
against the pin; compiles (syntax-checked against the installed headers);
not yet built or run.

## Upstreaming plan

- Where: a pull request to llvm/llvm-project citing #206083, whose
  `vector.yield` case part 1 also fixes; a new issue with `never.mlir`.
- Upstream test: the two cases the patch adds to
  `mlir/test/Dialect/UB/inlining.mlir`; run `check-mlir`, since any
  dialect whose single-block callee ends in a terminator that is not
  `ReturnLike` now takes the multi-block path.
- Status: not sent.
