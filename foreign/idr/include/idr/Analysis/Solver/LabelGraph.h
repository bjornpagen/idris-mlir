// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve's graph and its sets (Labels.h): the union-find over the
// reading's points, the waves that solve it, and the table that holds each
// set of labels once. Every table here is indexed by a number the reading
// or the table minted; nothing here holds an IR handle but the reading the
// graph takes, whose points and sinks it hands to the solution.
#ifndef IDR_ANALYSIS_SOLVER_LABELGRAPH_H
#define IDR_ANALYSIS_SOLVER_LABELGRAPH_H

#include "idr/Analysis/Labels.h"
#include "idr/Analysis/Solver/UnionFind.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/ArrayRef.h"

#include <cstdint>
#include <utility>

namespace idr::labels {

// The sets of one solve, each held once. A set is its members in label
// order; equal sets are one id; the union of the same ids is made once.
// Sets no class holds any more stay until the solve ends, with the table.
// Its arena and its two hashed tables, keyed by content no numbering
// covers, are the footprint's.
class SetTable {
public:
  SetTable();

  // The id of the set of `members`, sorted and unique.
  SetId intern(llvm::ArrayRef<Label> members);
  // The id of the union of `inputs`, which it may reorder. Where at most
  // one distinct set is not empty, that set's id, and no label is read.
  SetId unite(footprint::Vector<SetId> &inputs);
  // The members of `set`, in label order.
  llvm::ArrayRef<Label> members(SetId set) const;
  // How many sets the table holds: every SetId it made is below this.
  std::uint32_t size() const { return static_cast<std::uint32_t>(sets.size()); }
  // The labels the table has read to intern and unite.
  std::uint64_t labelsRead() const { return read; }

private:
  // Whether every label of `part` is one of `whole`'s.
  bool within(SetId part, SetId whole);

  std::uint64_t read = 0;
  footprint::BumpPtrAllocator storage;
  // Each set's members, by id, in `storage`.
  footprint::Vector<llvm::ArrayRef<Label>> sets;
  // Each set's id, by its members.
  footprint::DenseMap<llvm::ArrayRef<Label>, SetId> ids;
  // The union of each sorted tuple of two or more distinct ids met, the
  // tuple in `storage`.
  footprint::DenseMap<llvm::ArrayRef<SetId>, SetId> unions;
};

// The graph and its solver. It takes the reading whole: each point is a
// node, each source waits for the first wave, each link is an edge, and a
// dispatch runs nothing until the first wave ends. The solve (Labels.cpp)
// runs waves over the classes of the union-find until no firing adds an
// edge, and hands the points and their sets to the Solution.
class Graph {
public:
  Graph(Read reading, mlir::MLIRContext *context);

  // The least solution of the statements, what the waves read added to
  // `work`; the graph is spent.
  Solution solve(solver::Work &work) &&;

private:
  // What a class of the union-find holds; only a root's is current: the
  // id of its set, and the nodes whose classes include it.
  struct Class {
    SetId labels{};
    footprint::Vector<Node> successors;
  };
  // A dispatch's node of its callee, and the labels it has run, a subset of
  // its callee's set that grows to it at each wave's end; its call is the
  // reading's dispatch of the same number.
  struct Run {
    Node callee;
    SetId ran{};
  };

  // The statements as edges: each source waits for the first wave, each
  // link joins its nodes.
  void take(const Statements &statements);

  void seed();

  // Edges.
  void link(Node from, Node to, Link how);
  void include(Node from, Node to);
  Node merge(Node x, Node y);

  // Solving.
  footprint::Vector<Firing> wave();
  void fire(Firing firing);

  // The reading: its points and sinks, handed to the solution, and its
  // dispatches, which each firing reads.
  Read read;
  mlir::MLIRContext *context;

  // The union-find over the points, which merge links by its own rule.
  solver::UnionFind<Node> forest;
  footprint::Vector<Class> classes;
  SetTable sets;

  // Where each label starts, until the first wave.
  footprint::Vector<std::pair<Node, Label>> sources;
  // By dispatch.
  footprint::Vector<Run> runs;

  // What the next wave owes: the targets of the edges added since the
  // last, and those edges, each owed its source's set.
  footprint::Vector<Node> dirty;
  footprint::Vector<std::pair<Node, Node>> added;

  // The wave each node's class was last taken in, and its vertex there:
  // a wave reads only the classes it takes.
  footprint::Vector<std::uint32_t> takenIn;
  footprint::Vector<std::uint32_t> vertexIn;
  std::uint32_t waves = 0;

  // The classes, edges, dispatches and new labels the waves read.
  std::uint64_t steps = 0;
};

// A class a wave takes, numbered by its wave: the vertices of the wave's
// graph of inclusions, whose components the solver layer finds.
struct WaveVertexTag {
  using Minter = Graph;
};
using WaveVertex = Id<WaveVertexTag>;

} // namespace idr::labels

#endif // IDR_ANALYSIS_SOLVER_LABELGRAPH_H
