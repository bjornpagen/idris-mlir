<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] OperationEquivalence cannot compare symbol references by class

On llvm main at 416f328b (the pin), `OperationEquivalence` compares two
operations' discardable attributes and the types of their operands,
results and block arguments by identity and their properties with
`compareOpProperties`, and hashes them the same way
(`mlir/lib/IR/OperationSupport.cpp`, `isEquivalentTo`,
`isRegionEquivalentTo`, `computeHash`, *read*). Two functions whose bodies differ only in which callee they
name are never equivalent, even when the callees are: partition
refinement, which deduplicates functions by refining classes of them
until each is stable, needs to compare a call by its callee's class. The
compiler's deduplicator was a port of Modular's
`EliminateDuplicateFunctions` with a comparison of its own for that
reason (proposals/0000 C10); it is retired for partition refinement over
upstream's `OperationEquivalence`, and this hook is what that needs.

## Reproduce

The patch's unit tests: two `foo.call` ops naming `@a` and `@b` are not
equivalent at the pin, whatever the caller knows of `@a` and `@b`; nor
are two ops whose result or operand types differ only in the symbol a
tensor's encoding names. Types of the idr dialect name function symbols
too (a closure family's labels), so without the types a deduplication
over the hook misses those merges, though it never merges wrongly
(L18).

## Patch

`llvm.patch`, applying after 77: `computeHash`, `isEquivalentTo` and
`isRegionEquivalentTo` take an optional `MapSymbolRefFn` giving the
attribute that stands for each symbol reference; every symbol reference
in both operations' attributes and properties, and in the types of their
operands, results and block arguments, is replaced by it before hashing
or comparison (`AttrTypeReplacer`, one per call, made only when a
comparison by identity fails), and what stands for a reference is not
mapped again, so a caller that passes none pays nothing. Unit tests
`OperationEquivalenceTest.MapSymbolRef` and `MapSymbolRefInTypes`. Not
built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project; upstream's own
  `duplicate-function-elimination` would use it to merge callers that
  differ only in which copy they call, which it cannot today.
- Upstream test: the unit tests above.
- The patch goes when the pin's `OperationEquivalence` compares symbol
  references through a caller's hook.
