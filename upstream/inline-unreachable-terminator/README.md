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
`inlineRegionImpl` (`mlir/lib/Transforms/Utils/InliningUtils.cpp:331`)
takes the single-block fast path for any single-block callee. It asks the
terminator's dialect (`InliningUtils.cpp:340`) to replace the call's
results with the terminator's operands, then erases the terminator and
splices the rest of the caller's block after the inlined operations
(`:341-346`).
`ub.unreachable` has no operands to forward, and nothing may follow it in
its block, so the default hook (`DialectInlinerInterface.td:106-107`) is
`llvm_unreachable`. The abort names the generated
`DialectInlinerInterface.h.inc:82`, which is that default. The multi-block
path would call the other default hook (`:89-90`), which is
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
family: `--inline` aborts in the default `handleTerminator` for a
single-block callee. There the terminator is `vector.yield`, which is
`ReturnLike`, so it stays on the fast path and this patch does not cover
it. Its pull request
[#206218](https://github.com/llvm/llvm-project/pull/206218) fixes the
vector dialect only, and `ub.unreachable` still aborts (checked at main
ed390ca4, October 2026). File a new issue and a pull request; the text
to paste is `submission.md`.

## Our workaround

None: the patch below is carried, and a function body that never returns
ends in `ub.unreachable`, as a match region that crashes does. Before the
patch, `Emit` (`epilogue` in `compiler/src/IdrisMLIR/Emit/Bodies.idr`),
`idr-prune` and `idr-tail-loops` ended such a body with `ub.poison` and
`func.return`, never reached, and the program's verifier refused a body
that ended in `ub.unreachable`.

The inliner's test of whether the caller's region may take a second block
reads the `SingleBlock` trait alone (it says so: it does not account for
`SizedRegion`). The idr dialect's match ops and array loops have one block
per region (`SizedRegion<1>`) and now declare `SingleBlock` too, so that a
call of a function that never returns, in such a region, stays a call
instead of leaving the region two blocks.

## Patch

`llvm.patch` implements both parts of the proposed fix: the single-block
fast path only for a `ReturnLike` terminator, the inliner pass treating
such a callee as multi-block for a caller region that must stay one
block, and `UBInlinerInterface::handleTerminator(Operation *, Block *)`
as a no-op. Tests in `mlir/test/Dialect/UB/inlining.mlir`. Built into
the pinned toolchain; the test passes with its `mlir-opt`, and
`tests/upstream/inline-unreachable-terminator` checks the reproducer.

## Upstreaming plan

Status: file a new issue and a pull request. LLVM uses GitHub pull
requests (https://llvm.org/docs/GitHub.html), not Bugzilla. The text to
paste is `submission.md`.

- Where: a new issue, with `never.mlir`, and a pull request of one
  commit. The pull request title and body are the squash commit message.
  Cite https://github.com/llvm/llvm-project/issues/206083 as the same
  family (`vector.yield`, which is `ReturnLike`; pull request
  https://github.com/llvm/llvm-project/pull/206218 covers that dialect
  only).
- Upstream test: the two cases the patch adds to
  `mlir/test/Dialect/UB/inlining.mlir`. Run `check-mlir`: a single-block
  callee whose terminator is not `ReturnLike` now takes the multi-block
  path.
- Author: Bjorn, as an individual, outside any employer. No
  `Assisted-by` trailer, and no `Contributed-by` in the source.
