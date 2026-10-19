// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The labels (functions) each closure and suspension of the program may be:
// MLton's 0CFA on the edges the ops declare through the flow interface,
// solved once in the constructor.
//
// The flow interface says how every carrier moves: closures, suspensions
// and counted references. Only a closure or a suspension carries a label,
// so the solve keeps the edges that carry one, and no other; a constant is
// looked into wherever it is held, since a constructor of any data type may
// hold a closure in a field.
//
// A point is a value of a closure or lazy carrier, a parameter or result of
// a function, or an anchor (a field of a data type, the elements of a
// shaped type, the forced state of a lazy type), one for every value of
// its kind, whatever value an edge names it through. The reading of the
// program (LabelSites.cpp) states, point by point, where each label starts,
// which points include or equal which, and which calls run the labels a
// point holds; the solve (Labels.cpp) and the check of its answer
// (idr-expect's labels-least) read the same statements. There is no
// unknown: the world is closed, every op that moves a closure declares
// how, and a set is a finite set of the program's functions. A value of any
// other carrier has no node and holds no label.
//
// The solve keeps a set of labels once, however many points hold it: a
// class of points holds the identity of its set, never a copy, so a
// program whose points share a few large sets is solved in time and space
// near the size of those sets, not of the points times their labels.
//
// The graph is spent by its solve, which leaves a Solution: every point's
// node, each node's labels and each operand's sink, read and never written
// from then on.
#ifndef IDR_ANALYSIS_LABELS_H
#define IDR_ANALYSIS_LABELS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseMapInfoVariant.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Allocator.h"

#include <cstdint>
#include <optional>
#include <utility>
#include <variant>
#include <vector>

namespace idr {

// Whether a value of `type` carries labels: a closure or a suspension, at
// any grade. A value of any other type carries none, whatever it holds: an
// anchor holds the labels of its parts.
inline bool carriesLabels(mlir::Type type) {
  return !(Carriers::of(type) & Carriers::labels()).empty();
}

// Which parts of the program's constants hold a closure, each part answered
// once: a closure does, a constructor does when one of its fields does, and
// nothing else does.
class ClosureParts {
public:
  bool holds(mlir::Attribute part);

private:
  llvm::DenseMap<mlir::Attribute, bool> known;
};

namespace labels {

// A node of the graph: one per point, numbered as met.
enum class Node : unsigned {};
// A label, by its rank among the program's labels in name order: a set's
// members in rank order are its labels in the order of its ArrayAttr and
// of its sum's tags.
enum class Label : std::uint32_t {};
// A set of labels, interned: equal sets are one SetId, and SetId{0} is the
// empty set.
enum class SetId : std::uint32_t {};
// A dispatch (a call through a value, which runs each label its callee
// holds), by its number.
enum class Dispatch : unsigned {};

// A label that has reached a dispatch's callee: the label's edges, from
// the call's arguments to its parameters and from its results to the
// call's, are owed.
using Firing = std::pair<Dispatch, Label>;

// How a flow joins its two points: a suspension's two points hold one
// cell, so they hold one set, each included in the other; any other
// carrier's source is included in its target.
enum class Link : std::uint8_t { Include, Unify };

// The link of a flow of `carriers`: Unify when they hold a suspension. The
// one link rule, for an edge an op declares and for a label's edges at a
// dispatch.
Link linkOf(Carriers carriers);

// A point, normalized to one key whatever an edge names it through: the
// value of a use or of a whole value (a function's parameter is its entry
// argument), the anchor of a part, or a function's result by its name and
// position.
using ResultKey = std::pair<mlir::StringAttr, unsigned>;
using PointKey = std::variant<mlir::Value, FlowAnchor, ResultKey>;

// The key of `point` in the program of `table`: the one place a point is
// read.
PointKey keyOf(const mlir::SymbolTable &table, const FlowPoint &point);

// What the program states of its labels, point by point, as the reading
// meets it: a label starts at a point; one point's labels are at another
// (Include), or two points hold one set (Unify); a call runs each label a
// point holds, which owes the edges `readFiring` states. The solve builds
// its graph from them, and the check of its answer derives the least sets
// from them.
class Statements {
public:
  virtual ~Statements() = default;
  virtual void source(const PointKey &at, mlir::FlatSymbolRefAttr label) = 0;
  virtual void link(const PointKey &from, const PointKey &to, Link how) = 0;
  virtual void dispatch(const PointKey &callee, mlir::CallOpInterface call) = 0;
};

// States every edge of `program` that carries a label, and the constants'
// parts where they are held, into `to`; and gives each operand that moves
// a label its one sink in `sinks`. A use that moves into two points states
// them one set.
void readProgram(mlir::Operation *program, const mlir::SymbolTable &table, Statements &to,
                 llvm::DenseMap<mlir::OpOperand *, FlowPoint> &sinks);

// States the edges `label` owes at `call`, a dispatch that runs it: the
// call's arguments at the label's parameters after its captures, and its
// results at the call's.
void readFiring(const mlir::SymbolTable &table, mlir::CallOpInterface call,
                mlir::FlatSymbolRefAttr label, Statements &to);

// Whether every label of `a` is one of `b`'s, both sets of labelsOf (name
// order): a binary search in `b` for each label of `a`.
bool within(mlir::ArrayAttr a, mlir::ArrayAttr b);

// The position of `label` in `set`, a set of labelsOf (name order); none
// when the set does not hold it.
std::optional<unsigned> positionIn(mlir::ArrayAttr set, mlir::FlatSymbolRefAttr label);

// What the solve leaves: the node of every point an edge named, the labels
// of each node, and the one sink of each operand. It is never written once
// made, so it is read from any thread.
class Solution {
public:
  // The labels at the point `key`; the empty set where no label reaches.
  mlir::ArrayAttr labelsOf(const PointKey &key) const;
  // The key of `point`.
  PointKey keyOf(const FlowPoint &point) const { return labels::keyOf(table, point); }
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const;
  FuncOp function(mlir::StringAttr label) const { return table.lookup<FuncOp>(label); }

private:
  friend class Graph;
  explicit Solution(const mlir::SymbolTable &table);

  const mlir::SymbolTable &table;
  mlir::ArrayAttr empty;
  // The points that have nodes.
  llvm::DenseMap<PointKey, Node> nodes;
  // Each operand's one sink.
  llvm::DenseMap<mlir::OpOperand *, FlowPoint> sinks;
  // Each node's labels in name order, one uniqued attribute per set.
  std::vector<mlir::ArrayAttr> labels;
};

// The sets of one solve, each held once. A set is its members in rank
// order; equal sets are one id; the union of the same ids is made once.
// Sets no class holds any more stay until the solve ends, with the table.
class SetTable {
public:
  SetTable();

  // The id of the set of `members`, sorted and unique.
  SetId intern(llvm::ArrayRef<Label> members);
  // The id of the union of `inputs`, which it may reorder. Where at most
  // one distinct set is not empty, that set's id, and no label is read.
  SetId unite(llvm::SmallVectorImpl<SetId> &inputs);
  // The members of `set`, in rank order.
  llvm::ArrayRef<Label> members(SetId set) const;

private:
  // Whether every label of `part` is one of `whole`'s.
  bool within(SetId part, SetId whole) const;

  llvm::BumpPtrAllocator storage;
  // Each set's members, by id, in `storage`.
  std::vector<llvm::ArrayRef<Label>> sets;
  // Each set's id, by its members.
  llvm::DenseMap<llvm::ArrayRef<Label>, SetId> ids;
  // The union of each sorted tuple of two or more distinct ids met, the
  // tuple in `storage`.
  llvm::DenseMap<llvm::ArrayRef<SetId>, SetId> unions;
};

// The graph and its solver. The build (LabelSites.cpp) gives each point a
// node and records the statements; the solve (Labels.cpp) runs waves over
// the classes of the union-find until no firing adds an edge, and hands
// the points and their sets to the Solution.
class Graph {
public:
  explicit Graph(const mlir::SymbolTable &table);

  void walk(mlir::Operation *program);
  // The least solution of the statements; the graph is spent.
  Solution solve() &&;

private:
  // What a class of the union-find holds; only a root's is current: the
  // id of its set, and the nodes whose classes include it.
  struct Class {
    SetId labels{};
    llvm::SmallVector<Node, 2> successors;
  };
  // A dispatch: its call, the node of its callee, and the labels it has run,
  // a subset of its callee's set that grows to it at each wave's end.
  struct Run {
    mlir::CallOpInterface call;
    Node callee;
    SetId ran{};
  };

  // The solve's reading of the statements: a point is its node, a source
  // waits for the labels' ranks, an edge links the nodes, and a dispatch
  // runs nothing until the first wave ends.
  class Builder final : public Statements {
  public:
    explicit Builder(Graph &graph) : graph(graph) {}
    void source(const PointKey &at, mlir::FlatSymbolRefAttr label) override;
    void link(const PointKey &from, const PointKey &to, Link how) override;
    void dispatch(const PointKey &callee, mlir::CallOpInterface call) override;

  private:
    Graph &graph;
  };

  // Building.
  Node nodeOf(const PointKey &key);
  Node fresh();
  Node find(Node node);
  void rank();

  // Edges.
  void link(Node from, Node to, Link how);
  void include(Node from, Node to);
  Node merge(Node x, Node y);

  // Solving.
  llvm::SmallVector<Firing> wave();
  void fire(Firing firing);

  // The points as they are met, handed over by the solve.
  Solution out;

  // The union-find, by node.
  std::vector<Node> parents;
  std::vector<Class> classes;
  SetTable sets;

  // Where each label starts, by name until the labels are ranked.
  std::vector<std::pair<Node, mlir::FlatSymbolRefAttr>> sources;
  // Labels by rank: name order.
  std::vector<mlir::FlatSymbolRefAttr> labelNames;
  std::vector<Run> runs;

  // What the next wave owes: the targets of the edges added since the
  // last, and those edges, each owed its source's set.
  std::vector<Node> dirty;
  std::vector<std::pair<Node, Node>> added;
};

} // namespace labels

class Labels {
public:
  Labels(mlir::Operation *program, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Labels>() || !pa.isPreserved<mlir::SymbolTable>();
  }

  // The labels a closure or suspension at a point may be: a uniqued
  // ArrayAttr of FlatSymbolRefAttr in name order, the empty ArrayAttr where
  // no label reaches. A point whose carrier carries no label holds the
  // empty set. Two equal sets are one attribute. A part of a value is its
  // anchor, the same for every value of its kind.
  mlir::ArrayAttr labelsOf(mlir::Value value) const { return solution.labelsOf(value); }
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const {
    return solution.labelsOf(solution.keyOf(point));
  }
  mlir::ArrayAttr labelsOf(const FlowAnchor &anchor) const { return solution.labelsOf(anchor); }
  mlir::ArrayAttr labelsAt(const labels::PointKey &key) const { return solution.labelsOf(key); }

  // The labels `runner` runs: those of the closure or suspension it
  // carries (an idr.apply's callee, an idr.force's cell).
  mlir::ArrayAttr runs(RunsLabelsOpInterface runner) const {
    return labelsOf(runner.getLabelCarrier());
  }

  // The one point `operand` moves its value into at its op, or nothing: an
  // operand of a carrier that carries no label, and the callee and the
  // arguments of a dispatch, which move per label.
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const {
    return solution.sinkOf(operand);
  }

  // The function of `label`, from the program's table.
  FuncOp function(mlir::StringAttr label) const { return solution.function(label); }

private:
  labels::Solution solution;
};

} // namespace idr

#endif // IDR_ANALYSIS_LABELS_H
