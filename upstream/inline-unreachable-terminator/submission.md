# File the `ub.unreachable` inliner abort

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

`llvm.patch` (against `llvmorg-23.1.2`; rebase onto current `main` if it
does not apply). Apply it with `git apply` and make the one commit
above.

Tests live in the patch: `mlir/test/Dialect/UB/inlining.mlir` (a call of
a function that never returns is inlined into a function, and stays a
call in an `scf.for`). Run `check-mlir`.

## Steps

1. Open https://github.com/llvm/llvm-project/issues/new and paste the
   issue title and issue body. The `[mlir]` prefix is what the issue bot
   uses to add the mlir label.
2. Apply `llvm.patch` on a fork of `llvm/llvm-project`, one commit, and
   open the pull request into `main`. Paste the pull request title and
   body.
3. After the issue exists, add `Fixes #<issue number>` as the last
   paragraph of the pull request body. Leave
   https://github.com/llvm/llvm-project/issues/206083 open:
   `vector.yield` is `ReturnLike`, so this change leaves that case on
   the fast path.

No `@` mentions in the issue or the pull request.

## Issue title

```
[mlir] --inline aborts on a callee that ends in ub.unreachable
```

## Issue body

```
## Symptom

At llvmorg-23.1.2, `mlir-opt --inline` aborts when it inlines a
single-block callee whose terminator is `ub.unreachable` (a function
that never returns: it traps, or its body is proved impossible). The
abort is still present on main at ed390ca4 (October 2026).

## Reproducer

never.mlir:

    func.func private @never() -> i32 {
      ub.unreachable
    }

    func.func @main() -> i32 {
      %0 = func.call @never() : () -> i32
      return %0 : i32
    }

## Command

    mlir-opt never.mlir --inline

## Actual

`mlir-opt` aborts, exit status 134:

    must implement handleTerminator in the case of one inlined block
    UNREACHABLE executed at .../mlir/Transforms/DialectInlinerInterface.h.inc:82!

## Expected

`mlir-opt` exits 0. `@main` becomes `ub.unreachable` (the call is gone),
or the call stays.

## Cause

`inlineRegionImpl` (mlir/lib/Transforms/Utils/InliningUtils.cpp:331)
takes the single-block fast path for any one-block callee the dialect
allows. That path (InliningUtils.cpp:340) calls
`handleTerminator(Operation *, ValueRange)` so the dialect can replace
the call's results with the terminator's operands, then erases the
terminator and splices the rest of the caller's block after the inlined
operations (InliningUtils.cpp:341-346).

`ub.unreachable` has no operands to forward, and nothing may follow it
in its block. `UBInlinerInterface`
(mlir/lib/Dialect/UB/IR/UBOps.cpp:25-32) makes every `ub` operation
legal to inline and implements neither `handleTerminator` hook. The
one-block default
(mlir/include/mlir/Transforms/DialectInlinerInterface.td:106-107) is
`llvm_unreachable` with the message above. The abort's
`DialectInlinerInterface.h.inc:82` is that generated default. The
multi-block overload's default (DialectInlinerInterface.td:89-90) is
`llvm_unreachable` as well.

https://github.com/llvm/llvm-project/issues/206083 is the same abort,
with `vector.yield` as the terminator. `vector.yield` is `ReturnLike`,
so it is a different case of the missing hook.
https://github.com/llvm/llvm-project/pull/206218 fixes the vector
dialect only.
```

## Pull request title

```
[mlir] Inline a callee that ends in ub.unreachable
```

## Pull request body

```
Inlining a single-block callee that ends in ub.unreachable aborts in
the default handleTerminator. The single-block fast path treats that
terminator as a return: it forwards the terminator's operands to the
call's results, erases the terminator, and splices the rest of the
caller's block after the inlined operations. ub.unreachable has nothing
to forward, and nothing may follow it. The ub dialect implements
neither handleTerminator hook, so the default is llvm_unreachable
("must implement handleTerminator in the case of one inlined block").

https://github.com/llvm/llvm-project/issues/206083 is the same abort
for vector.yield. That operation is ReturnLike, and
https://github.com/llvm/llvm-project/pull/206218 covers the vector
dialect only, so a callee that ends in ub.unreachable still aborts.

The fast path is only right for a ReturnLike terminator. Any other
single-block callee is inlined as a block of its own, and a caller
region that must stay one block keeps the call.
UBInlinerInterface::handleTerminator(Operation *, Block *) is empty, so
ub.unreachable stays the terminator of the inlined block and the code
after the call is unreachable.
```
