<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] CallGraph is built by recursion on nesting depth

On llvm main at 416f328b (the pin), `computeCallGraph`
(`mlir/lib/Analysis/CallGraph.cpp`, *read*) calls itself for every op
nested in every region, once per level of nesting, and `CallGraph`'s
constructor runs it twice. Building the call graph of deeply nested IR
needs a native stack that grows with the depth of the IR; under the
compiler's one small, measured stack for every thread (proposals/0000
D33, C43, C99), the depth of a program would be a limit on what the
compiler accepts.

## Reproduce

A module whose function nests a region N deep under
`-test-print-callgraph` on a thread with a small stack: native depth
linear in N (*read*; no overflowing depth measured).

## Patch

`llvm.patch`, applying after 73 (the same file): the same ops visited in
the same pre-order from an explicit worklist, each entry carrying the
node of its enclosing callable, so nodes are made (and 73's indices
minted) and edges added in the order they were. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request, after the RFC on Discourse for the family of
  MLIR's recursions on input size (92's README).
- Upstream test: `test-callgraph.mlir` unchanged, and a deep-nesting
  input on a small stack.
- The patch goes when the pin builds the call graph without recursion on
  nesting depth.
