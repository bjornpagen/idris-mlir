<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] CallGraph has no dense node ids and keeps no components

On llvm main at 416f328b (the pin), `mlir::CallGraph` names its nodes by
pointer (`mlir/include/mlir/Analysis/CallGraph.h`, *read*): a client that
keeps state per node keeps it in a map keyed by `CallGraphNode *`, and
every client that needs the strongly connected components runs
`scc_iterator` itself (the inliner, `print`, transform's call-graph
utility). The compiler's solver layer solves bottom-up over components
with per-node state in vectors, so it built a graph of its own beside
upstream's, and the next upstream pass we adopt (the inliner) builds
`mlir::CallGraph` beside that: two call graphs, two component orders
(proposals/0000 C33, L06 I4).

## Reproduce

Nothing to run: what is missing is an API (*read*).

## Patch

`llvm.patch`, applying after 72, in the shape the coordinator fixed:

- `CallGraphNode::getIndex()`: a dense id the graph mints when it makes
  a node (the external caller node 0, the unknown callee node 1, then in
  order of creation), never reused and never changed for the graph's
  life; `CallGraph::getNumIndices()` sizes per-node vectors; the graph
  traits give it as `getNumber`/`getMaxNumber`, so `scc_iterator` (72)
  and `po_iterator` keep their state in vectors.
- `CallGraph::getSCCs()`: the components reachable from the external
  node, bottom-up, each an `ArrayRef<CallGraphNode *>` over one
  permutation the graph keeps, computed on the first call and dropped
  when a node is added or erased (`invalidateSCCs()` for a client that
  adds edges). `print` reads them, so `test-callgraph.mlir`'s SCC checks
  cover the order.

What upstream cannot hold stays ours, in the solver layer's program
graph: tail kinds, call sites, and the editor that restructures and
refreezes the graph (proposals/0000 C33, D2). Not built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: an RFC on Discourse, "Dense node ids and kept SCCs for
  mlir::CallGraph": what the graph lacks (an id a vector can be indexed
  by; its components without a traversal per client), who needs it (the
  inliner's own SCC walk and use lists, which key by node pointer;
  out-of-tree analyses that solve bottom-up over components), and the
  API above; then the pull request with 72 before it.
- Upstream test: `test-callgraph.mlir`'s SCC checks; a unit test that the
  indices are dense and stable across `eraseNode`.
- The patch goes when the pin's `CallGraph` has dense ids and kept
  components (in this form or another that keeps every fact this one
  gives the solver layer).
