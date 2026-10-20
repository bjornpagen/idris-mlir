<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] CSE replaces the linalg.index of a nested structured op by the enclosing op's

On llvm main at 7208ba24 (the pin), and still on main on 2026-10-19,
`cse` merges a `linalg.index` in the body of a `linalg.generic` nested in
another's body with the outer generic's `linalg.index` of the same
dimension. `linalg.index` is the iteration index of its parent structured
op, but it is `Pure` and has no operand, so
`OperationEquivalence::isEquivalentTo` finds the two identical, and the
CSE driver (`mlir/lib/Transforms/Utils/CSE.cpp`, `simplifyBlock`) keeps
one scope of known values across every nested region that is not
`IsolatedFromAbove`: the inner index finds the outer one and is replaced
by it.

Upstream knows the bug: issue #62644 (open since 2023-05, the same
merge after `linalg.map` and an inlined `tensor.generate`), pull request
#68894 (open, stalled: it drops `Pure`, which the Linalg maintainers
refused because it stops CSE inside a body), and the 2025 Discourse
thread "Bug in OperationEquivalence (breaks -cse on linalg.index)", which
asked for a trait saying that two such ops are equivalent only under the
same parent, and ended with no fix. There is nothing to backport.

## Reproduce

`nested-linalg-index.mlir`, with the toolchain's `mlir-opt --cse`: the
inner generic yields the outer `linalg.index 0`, and one `linalg.index`
is left of three (two of the outer generic, one of the inner). In the
compiler this was a silent miscompile: idr-structure-loops makes an array
tabulated in a tabulate's body a `linalg.generic` nested in the outer
one's body, and the cse after idr-bufferize made the column index read
the row index (tests/linarray-rows-crash-order printed -16 for -9, and
divided by 0 where no crash was due; the arrays-refused audit at
3c8a666a, §2 group C).

## Expected

Two `linalg.index` ops are one value only under the same structured op:
the inner index stays, and the outer generic's two indices of the same
dimension are still one.

## The fix

`llvm.patch` states what `linalg.index` is: an op whose value depends on
its parent, the new trait `DependsOnParent` (`OpBase.td`,
`OpDefinition.h`, documented in `Traits/_index.md`). CSE's key for known
values includes the parent of such an op, so an op of another parent is
never equal to it. It needs no more: the verifier of `linalg.index`
requires its immediate parent to be the `LinalgOp` it indexes, so no op
other than the index itself can carry a free reference to an enclosing
op's iteration (an op whose region holds a `linalg.index` is that
index's structured op). The check is in CSE's key, not in
`OperationEquivalence`, because comparing two structured ops compares
their bodies, whose indices have different parents and are equivalent.

The alternatives, and why not:
- dropping `Pure` (#68894) gives the op unknown effects, so nothing
  inside a body is CSE'd with it or erased when dead;
- a read effect on a Linalg resource reaches every structured op with an
  index through `RecursiveMemoryEffects`, so none is memory-effect-free
  any more (no hoisting by LICM, kept by remove-dead-values, and every
  `isMemoryEffectFree` client of ours, idr-narrow's among them);
- a CSE barrier at the regions of structured ops would also stop CSE of
  ops that do not read the index.

The test is `nested_linalg_index` in `mlir/test/Transforms/cse.mlir`.

## Patch

`llvm.patch`, applied by tools/bootstrap.sh; checked by
tests/upstream-cse-nested-linalg-index (two indices are left: each
generic keeps one).

## Testing at the pin

Built into a private mlir-opt (Release, assertions, arm64 macOS) from the
pin with every carried patch and 56, 57 and 58's diff. The patch applies to
the pristine pin alone and after every carried patch. The reproducer is
fixed, the new test passes, and fails on the toolchain's mlir-opt. check-mlir
on that build, with patch 24 as amended on 2026-10-19: 4100 passed, 639
unsupported, 1 skipped, 1 expectedly failed, none failed.

## Upstreaming plan

A comment on #62644 and a PR to llvm/llvm-project, `[mlir] Add the
DependsOnParent trait; CSE linalg.index only under one parent`, Fixes
#62644, with the cse.mlir test; a new core trait may first want a short
RFC on Discourse, linked from the thread above. Status: not filed;
carried; check-mlir passes on a private build.
