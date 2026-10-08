# [mlir] Inlining a single-block callee that does not return aborts

At `llvmorg-23.1.2`, `--inline` aborts when it inlines a single-block
callee whose terminator does not return to the caller: one that ends in
`ub.unreachable` (a function that traps, or whose body is proved
impossible), or an `llvm.func` that ends in `llvm.unreachable` called from
anywhere but another `llvm.func`.

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
UNREACHABLE executed at .../mlir/Transforms/DialectInlinerInterface.h.inc:81!
```

`llvm-unreachable.mlir` (an `llvm.func` ending in `llvm.unreachable`,
called from a `func.func`) aborts the same way in another place:

```
$ mlir-opt llvm-unreachable.mlir --inline
... llvm::cast(From*) [with To = mlir::LLVM::ReturnOp ...]: Assertion
`isa<To>(Val) && "cast<Ty>() argument of incompatible type!"' failed.
```

Both exit 134. Expected: the callee is inlined, its terminator stays the
end of its block, and the code after the call is unreachable; inside a
region that must stay one block (`scf.for`), the call stays.

## Cause

`inlineRegionImpl` (`mlir/lib/Transforms/Utils/InliningUtils.cpp:328-346`)
takes a fast path for a single inlined block: it calls the single-block
`handleTerminator` to forward the terminator's operands to the call's
results, erases the terminator (`:341`) and continues the block with the
operations after the call. That is only right for a terminator that returns
to the caller. A dialect declines the fast path through
`allowSingleBlockOptimization`, and the LLVM dialect does so for
`llvm.unreachable` (`LLVMIR/Transforms/InlinerInterfaceImpl.cpp:785`).

Three things are wrong:

- `InlinerInterface::allowSingleBlockOptimization` (`InliningUtils.cpp:147`)
  asks the dialect of the block's parent op. After cloning, that block
  lives in the caller's region, so the caller's dialect answers, not the
  terminator's. The LLVM opt-out only works when the caller is an
  `llvm.func`; otherwise `llvm.unreachable` reaches the single-block
  `handleTerminator`, which does `cast<LLVM::ReturnOp>` (`:796`).
- The `ub` dialect (`mlir/lib/Dialect/UB/IR/UBOps.cpp:25`) declines
  nothing and implements neither `handleTerminator`; the single-block
  default is `llvm_unreachable` (`DialectInlinerInterface.td:107`).
- The inliner pass (`Inliner.cpp:727`) checks whether the caller's region
  can take new blocks only for a callee with two or more blocks, so a
  callee that declines the fast path would be split into an `scf.for`
  body.

No generic data can make the decision instead: `ub.unreachable` and
`transform.yield` are both terminators with no successors and no
`ReturnLike`, and only `transform.yield` returns. A fast path gated on
`ReturnLike` (the previous version of this patch) sends
`transform.include` of a named sequence to the multi-block path, where
the transform dialect's default `handleTerminator` aborts; that was
checked with a linked `mlir-opt`.

## Proposed fix

`allowSingleBlockOptimization` is asked of the terminator's dialect, as
`handleTerminator` is. The inliner pass treats a single-block callee that
declines the fast path like a multi-block one. The `ub` dialect declines it
for `ub.unreachable` and leaves `ub.unreachable` in place in the
multi-block `handleTerminator`.

## Status upstream

Not filed. Still broken on `main` at 7208ba24 (2026-10-08): the fast
path, `InlinerInterface::allowSingleBlockOptimization` and
`UBInlinerInterface` are unchanged since `llvmorg-23.1.2`. The hook
itself came from [#122646](https://github.com/llvm/llvm-project/pull/122646),
for `llvm.unreachable` in an `llvm.func`; its review left dialects whose
regions keep one block to "something else". It is the mechanism trunk
has for this case; there is no trait or interface that says a terminator
does not return. The open issue
[#206083](https://github.com/llvm/llvm-project/issues/206083) is the same
abort with `vector.yield` as the terminator of an `llvm.func`.
`vector.yield` is `ReturnLike` and keeps the fast path, so this patch does
not close it; its pull request
[#206218](https://github.com/llvm/llvm-project/pull/206218), still open,
changes the vector dialect only, and reviewers there consider that input
invalid IR. File a new issue and a pull request; the text to paste is
`submission.md`.

## Our workaround

None: the patch is carried, and a function body that never returns ends
in `ub.unreachable`, as a match region that crashes does. Before the
patch, `Emit` (`epilogue` in `compiler/src/IdrisMLIR/Emit/Bodies.idr`),
`idr-prune` and `idr-tail-loops` ended such a body with `ub.poison` and
`func.return`, never reached, and the program's verifier refused a body
that ended in `ub.unreachable`.

The inliner's test of whether the caller's region may take a second block
reads the `SingleBlock` trait alone (it says so: it does not account for
`SizedRegion`). The idr dialect's match ops and array loops have one block
per region (`SizedRegion<1>`) and declare `SingleBlock` too, so that a
call of a function that never returns, in such a region, stays a call
instead of leaving the region two blocks.

## Patch

`llvm.patch` against `llvmorg-23.1.2`, which `tools/bootstrap.sh`
applies, and `pull-request.diff`, the same change against `main` at
7208ba24, which this repository does not apply. They differ only in the
call of `shouldInline` in `inlineCallsInSCC`, which `main` also gates on
`blockedEdges` (#211377). `InliningUtils.cpp` asks the terminator's
dialect; `Inliner.cpp` passes the inliner interface to `shouldInline`
and counts a declined fast path as needing new blocks; `UBOps.cpp`
declines it for `ub.unreachable` and keeps the op in the multi-block
hook; `DialectInlinerInterface.td` documents which dialect the hook is
asked of. Tests in `mlir/test/Transforms/inlining.mlir`.
`tests/upstream/inline-unreachable-terminator` checks `never.mlir`.

Verified: `llvm.patch` applies to the pinned tree and
`pull-request.diff` to `main` (`git apply --check`). Against the pin,
the three changed `.cpp` files compiled and linked into an `mlir-opt`
with the test dialect: the patched `Transforms/inlining.mlir` passes all
five RUN lines (the unpatched `mlir-opt` aborts on it), and every other
`-inline` test in `mlir/test` gives the same result as the unpatched
build. Against `main`'s headers (generated files from the pinned
`mlir-tblgen`), `Inliner.cpp` and `InliningUtils.cpp` pass
`-fsyntax-only`; `UBOps.cpp` fails only in `ub.poison`'s generated code,
which the pinned `mlir-tblgen` cannot produce for `main`. Changed lines
are clang-format clean. On `main` itself, see Testing on main.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (each directory's `pull-request.diff`, else its
`llvm.patch`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

Then, with this patch's source changes alone reverted (`Inliner.cpp`,
`InliningUtils.cpp`, `UBOps.cpp`, the `.td` documentation):
`Transforms/inlining.mlir` fails; with them back,
it passes.

## Upstreaming plan

Status: file a new issue and a pull request, with the text in
`submission.md`. LLVM uses GitHub pull requests
(https://llvm.org/docs/GitHub.html), not Bugzilla.

- Where: a new issue with `never.mlir` and `llvm-unreachable.mlir`, and a
  pull request of one commit, `pull-request.diff`, against `main`. The
  pull request title and body are the squash commit message; the body
  ends `Fixes #<issue>`.
- Upstream test: the three cases the patch adds to
  `mlir/test/Transforms/inlining.mlir`, next to the existing multi-block
  callee cases (see Testing on main).
- Author: Bjorn, as an individual, outside any employer, with
  `Assisted-by: Claude Code` as the last line (llvm/docs/AIToolPolicy.md);
  no `Contributed-by` in the source.
- Dropped when the pin moves past the merged fix.
