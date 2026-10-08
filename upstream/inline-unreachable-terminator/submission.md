Approach changed: the old patch took the single-block fast path only for ReturnLike terminators, which broke transform.yield; now allowSingleBlockOptimization is asked of the terminator's dialect, as handleTerminator already is, and the inliner treats a declined fast path like a multi-block callee.

# File the inliner abort on a callee that does not return

## Status

Still broken on `main` at 7208ba24 (2026-10-08): `inlineRegionImpl`,
`InlinerInterface::allowSingleBlockOptimization` and `UBInlinerInterface`
are as at `llvmorg-23.1.2`. No open issue or pull request covers it. File
one issue and one pull request on https://github.com/llvm/llvm-project.
LLVM uses GitHub issues and pull requests, not Bugzilla.

## Author

Bjorn, as an individual, outside any employer. Commit with a personal
email that the GitHub account publishes. No `Assisted-by` trailer, no
`Contributed-by`, no `@` mentions in the issue, the pull request, or a
comment.

## Diff

`pull-request.diff` in this directory, against `main` at 7208ba24. It is
one commit whose message is the pull request title and body below. It
has no `From:` line: apply it with `git apply` and commit it as yourself
with that message. It is the same
change as `llvm.patch`, which this repository applies to
`llvmorg-23.1.2`; only the call of `shouldInline` in `inlineCallsInSCC`
differs, because `main` also checks `blockedEdges` there. Run
`check-mlir` before opening the pull request.

## Steps

1. Open https://github.com/llvm/llvm-project/issues/new and paste the
   issue title and body.
2. Push the commit to a branch of a fork and open the pull request into
   `main` with the title and body below; GitHub squash-merges, and the
   landed commit is that title and body.
3. Replace `#<issue>` in the last line of the body with the issue
   number.

## Issue title

```
[mlir] --inline aborts on a single-block callee that does not return
```

## Issue body

```
`mlir-opt --inline` aborts when it inlines a single-block callee whose
terminator does not return to the caller.

    // never.mlir
    func.func private @never() -> i32 {
      ub.unreachable
    }

    func.func @main() -> i32 {
      %0 = func.call @never() : () -> i32
      return %0 : i32
    }

    $ mlir-opt never.mlir --inline
    must implement handleTerminator in the case of one inlined block
    UNREACHABLE executed at .../mlir/Transforms/DialectInlinerInterface.h.inc:81!

The LLVM dialect declines the single-block fast path for
llvm.unreachable, but that only takes effect when the caller is an
llvm.func:

    // llvm-unreachable.mlir
    llvm.func @never() -> i32 {
      llvm.unreachable
    }

    func.func @main() -> i32 {
      %0 = llvm.call @never() : () -> i32
      return %0 : i32
    }

    $ mlir-opt llvm-unreachable.mlir --inline
    Assertion `isa<To>(Val) && "cast<Ty>() argument of incompatible type!"'
    failed.

The cast is the cast<LLVM::ReturnOp> in the LLVM dialect's single-block
handleTerminator. The same call inside an scf.for in an llvm.func aborts
the same way.

Expected: the callee is inlined, its terminator stays the end of its
block, and the operations after the call move to a block that nothing
branches to. Inside a region that must stay one block, such as an scf.for
body, the call is left alone.

Reproduced with llvmorg-23.1.2. On main (7208ba24) the code involved is
unchanged: InlinerInterface::allowSingleBlockOptimization asks the
dialect of the op enclosing the inlined block, which is the caller's, not
the terminator's, and the ub dialect declines nothing and implements
neither handleTerminator.

#206083 is a different abort on the same path: vector.yield as the
terminator of an llvm.func.
```

## Pull request title

```
[mlir][inliner] Fix inlining of single-block callees that do not return
```

## Pull request body

```
The inliner's single-block fast path forwards the operands of the
callee's terminator to the call results, erases the terminator, and
continues the block with the operations after the call. That is only
correct for a terminator that returns to the caller.
allowSingleBlockOptimization, added for llvm.unreachable in #122646, is
how a dialect declines the fast path, but InlinerInterface asks it of
the dialect of the op enclosing the inlined block, which after cloning
is the caller, not the callee. The LLVM dialect's opt-out therefore only
works when the caller is an llvm.func: inlined into a func.func, or into
an scf.for body, llvm.unreachable takes the fast path and the LLVM
handleTerminator asserts in cast<LLVM::ReturnOp>. The ub dialect
declines nothing, so a callee ending in ub.unreachable reaches the
default single-block handleTerminator, which is llvm_unreachable.

allowSingleBlockOptimization is now asked of the dialect of the inlined
block's terminator, as handleTerminator already is. A dialect that
implements the hook is now asked about its own terminators rather than
about blocks inlined into its ops; the LLVM dialect's implementation
needs no change. The inliner pass treats a single-block callee that
declines the fast path like a multi-block callee, so it does not inline
it into a region that must stay one block and leaves the call instead.
The ub dialect declines the fast path for ub.unreachable and keeps it as
the end of its block in the multi-block handleTerminator. The decision
stays with the dialect because no generic property separates the cases:
ub.unreachable and transform.yield are both successor-less terminators
without ReturnLike, and only transform.yield returns.

Tests in mlir/test/Transforms/inlining.mlir: a func.func ending in
ub.unreachable is inlined into a func.func and stays a call inside
scf.for, and an llvm.func ending in llvm.unreachable is inlined into a
func.func.

Fixes #<issue>
```
