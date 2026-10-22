<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [ADT] scc_iterator hashes every node of a numbered graph

On llvm main at 416f328b (the pin), `llvm::scc_iterator` keeps each
node's Tarjan visit number in a `DenseMap<NodeRef, unsigned>`
(`llvm/include/llvm/ADT/SCCIterator.h`, `nodeVisitNumbers`, *read*), one
hash lookup per edge, whatever the graph. `po_iterator` already keeps
its visited set in a vector indexed by `GraphTraits::getNumber` when the
graph numbers its nodes (`PostOrderIterator.h`, `po_detail::NumberSet`).
A call graph with dense node ids (`upstream/73-call-graph-dense-ids`)
and the solver layer's own graphs are such graphs: their components
are computed by hashing what a vector holds.

## Reproduce

Nothing to run: the cost is read in the code, one `DenseMap` probe per
visited edge and per pop.

## Patch

`llvm.patch`: `scc_detail::VisitNumbers<GT>`, a vector indexed by
`GT::getNumber` when the traits give it and the `DenseMap` otherwise,
with 0 for a node not visited (visit numbers count from 1);
`ReplaceNode` keeps its meaning, a null replacement (the MLIR inliner's
removal of an inlined node) giving the vector nothing to store. A unit
test runs every 4-node graph with and without numbers and checks the
same components in the same order. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[ADT]`, before 73's RFC
  (73 builds on it).
- Upstream test: `SCCIteratorTest.NumberedNodesGiveTheSameSCCs`.
- The patch goes when the pin's `scc_iterator` reads node numbers.
