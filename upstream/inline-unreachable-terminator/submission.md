Approach changed: the old patch took the single-block fast path only for ReturnLike terminators, which broke transform.yield; now allowSingleBlockOptimization is asked of the terminator's dialect, as handleTerminator already is, and the inliner treats a declined fast path like a multi-block callee.

# File the inliner abort on a callee that does not return

## Status

File a new issue and a pull request, both on
https://github.com/llvm/llvm-project.

LLVM uses GitHub pull requests (https://llvm.org/docs/GitHub.html), not
Bugzilla.

## Author

Bjorn, as an individual, outside any employer. Commit with a personal
email that the GitHub account publishes
(https://llvm.org/docs/GitHub.html, "Email Addresses").

Leave off any `Assisted-by` trailer. Leave `Contributed-by` out of the
commit message and out of the source.

## Commit

One commit, on a branch from a recent `main`, pushed to a fork. The pull
request title and body are the squash commit message: GitHub's
squash-merge uses them, and the messages of commits in the pull request
are not used (https://llvm.org/docs/GitHub.html). Use the title and body
below as that one commit's message.

## Patch

`llvm.patch` (against `llvmorg-23.1.2`). On `main`, the `Inliner.cpp`
hunk that passes `inlinerIface` to `shouldInline` needs a hand rebase:
the call in `inlineCallsInSCC` now also checks `blockedEdges`. The other
hunks apply. Tests live in the patch, in
`mlir/test/Transforms/inlining.mlir`. Run `check-mlir`.

## Steps

1. Open https://github.com/llvm/llvm-project/issues/new and paste the
   issue title and issue body.
2. Apply `llvm.patch` on a fork of `llvm/llvm-project`, one commit, and
   open the pull request into `main`. Paste the pull request title and
   body.
3. After the issue exists, add `Fixes #<issue number>` as the last
   paragraph of the pull request body. Leave #206083 open: this change
   does not touch `vector.yield`.

No `@` mentions in the issue or the pull request.

## Issue title

```
[mlir] --inline aborts on a single-block callee that does not return
```

## Issue body

```
At llvmorg-23.1.2 and on main, `mlir-opt --inline` aborts when it
inlines a single-block callee whose terminator does not return to the
caller.

    func.func private @never() -> i32 {
      ub.unreachable
    }

    func.func @main() -> i32 {
      %0 = func.call @never() : () -> i32
      return %0 : i32
    }

`mlir-opt never.mlir --inline`:

    must implement handleTerminator in the case of one inlined block
    UNREACHABLE executed at .../mlir/Transforms/DialectInlinerInterface.h.inc:81!

The LLVM dialect declines the single-block fast path for
llvm.unreachable, but only when the caller is an llvm.func. Called from
a func.func, it asserts instead:

    llvm.func @never() -> i32 {
      llvm.unreachable
    }

    func.func @main() -> i32 {
      %0 = llvm.call @never() : () -> i32
      return %0 : i32
    }

    Assertion `isa<To>(Val) && "cast<Ty>() argument of incompatible type!"'
    failed (cast<LLVM::ReturnOp> in the LLVM dialect's handleTerminator)

The same happens for that call inside an scf.for in an llvm.func.

Expected: the callee is inlined, its terminator stays the end of its
block, and the code after the call becomes unreachable. In a region that
must stay one block, such as an scf.for body, the call stays.

The single-block fast path in inlineRegionImpl
(mlir/lib/Transforms/Utils/InliningUtils.cpp) erases the terminator and
continues the block with the operations after the call.
InlinerInterface::allowSingleBlockOptimization, which lets a dialect
decline that, asks the dialect of the op enclosing the inlined block,
which is the caller's, not the terminator's. The ub dialect declines
nothing and implements neither handleTerminator.

#206083 is the same abort for vector.yield in an llvm.func. vector.yield
is ReturnLike, so it is a different case.
```

## Pull request title

```
[mlir] Fix inlining of single-block callees that do not return
```

## Pull request body

```
The inliner's single-block fast path forwards the callee's terminator
operands to the call results, erases the terminator, and continues the
block with the operations after the call. That is only correct for a
terminator that returns to the caller, and allowSingleBlockOptimization
is how a dialect declines it. InlinerInterface asks that hook of
the dialect of the op enclosing the inlined block, which after
cloning is the caller's, not the terminator's. The LLVM dialect's
opt-out for llvm.unreachable therefore only takes effect when the
caller is an llvm.func: inlined into a func.func or an scf.for,
llvm.unreachable takes the fast path and handleTerminator asserts in
cast<LLVM::ReturnOp>. The ub dialect declines nothing, so a callee
ending in ub.unreachable aborts in the default handleTerminator.

The hook is now asked of the dialect of the terminator, as
handleTerminator is. The inliner pass treats a single-block callee
whose terminator declines the fast path like a multi-block one, so
it is not inlined into a region that must stay a single block. The
ub dialect declines the fast path for ub.unreachable and leaves it in
place in the multi-block handleTerminator. This has to come from the
dialect: ub.unreachable and transform.yield are both successor-less
terminators without ReturnLike, and only one of them returns.

https://github.com/llvm/llvm-project/issues/206083 is the same abort
for vector.yield, which is ReturnLike and keeps the fast path; this
does not fix it.

Tests in mlir/test/Transforms/inlining.mlir: a callee ending
in ub.unreachable is inlined into a function and stays a call in
scf.for, and an llvm.func ending in llvm.unreachable is inlined into
a func.func.
```
