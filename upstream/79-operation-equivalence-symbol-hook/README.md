<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] OperationEquivalence cannot compare symbol references by class

On llvm main at 416f328b (the pin), `OperationEquivalence` compares two
operations' discardable attributes by identity and their properties
with `compareOpProperties`, and hashes them the same way
(`mlir/lib/IR/OperationSupport.cpp`, `isEquivalentTo`, `computeHash`,
*read*). Two functions whose bodies differ only in which callee they
name are never equivalent, even when the callees are: partition
refinement, which deduplicates functions by refining classes of them
until each is stable, needs to compare a call by its callee's class. The
compiler's deduplicator was a port of Modular's
`EliminateDuplicateFunctions` with a comparison of its own for that
reason (proposals/0000 C10); it is retired for partition refinement over
upstream's `OperationEquivalence`, and this hook is what that needs.

## Reproduce

The patch's unit test: two `foo.call` ops naming `@a` and `@b` are not
equivalent at the pin, whatever the caller knows of `@a` and `@b`.

## Patch

`llvm.patch`, applying after 78: `computeHash`, `isEquivalentTo` and
`isRegionEquivalentTo` take an optional `MapSymbolRefFn` giving the
attribute that stands for each symbol reference; every symbol reference
in both operations' attributes and properties is replaced by it before
hashing or comparison (`AttrTypeReplacer`), after the comparison by
identity, so a caller that passes none pays nothing. Unit test
`OperationEquivalenceTest.MapSymbolRef`. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project; upstream's own
  `duplicate-function-elimination` would use it to merge callers that
  differ only in which copy they call, which it cannot today.
- Upstream test: the unit test above.
- The patch goes when the pin's `OperationEquivalence` compares symbol
  references through a caller's hook.
