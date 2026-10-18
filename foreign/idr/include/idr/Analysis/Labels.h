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
// its kind, whatever value an edge names it through. Points are nodes of a
// union-find; a class holds the labels its points may be, the nodes its
// labels flow into, and the dispatches its labels run. There is no
// unknown: the world is closed, every op that moves a closure declares
// how, and a set is a finite set of the program's functions. A value of any
// other carrier has no node and holds no label.
//
// The graph is spent by its solve, which leaves a Solution: every point's
// node, each node's labels and each operand's sink, read and never written
// from then on.
#ifndef IDR_ANALYSIS_LABELS_H
#define IDR_ANALYSIS_LABELS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseMapInfoVariant.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

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
// A label, by its number, given when it is first met.
enum class Label : std::uint32_t {};
// A dispatch (a call through a value, which runs each label its callee
// holds), by its number.
enum class Dispatch : unsigned {};

// A label that has reached a node's class: owed to the class's successors
// and dispatches.
using Arrival = std::pair<Node, Label>;
// A label that has reached a dispatch's callee: the label's edges, from
// the call's arguments to its parameters and from its results to the
// call's, are owed.
using Firing = std::pair<Dispatch, Label>;
// One unit of the solve's work. Each enters the worklist at most once, and
// there are finitely many: the nodes and the dispatches, each with the
// labels, all made by the program's finitely many ops and constants.
using Work = std::variant<Arrival, Firing>;

// How a flow joins its two points: a suspension's two points hold one
// cell, so they are one class; any other carrier's source is included in
// its target.
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

// What the solve leaves: the node of every point an edge named, the labels
// of each node, and the one sink of each operand. It is never written once
// made, so it is read from any thread.
class Solution {
public:
  // The labels at the point `key`; the empty set where no label reaches.
  mlir::ArrayAttr labelsOf(const PointKey &key) const;
  // The key of `point`: the one place a point is read.
  PointKey keyOf(const FlowPoint &point) const;
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const;
  FuncOp function(mlir::StringAttr label) const { return table.lookup<FuncOp>(label); }

private:
  friend class Graph;
  explicit Solution(const mlir::SymbolTable &table);

  // The node of `key`; none for a point no edge named, which holds the
  // empty set.
  std::optional<Node> lookup(const PointKey &key) const;

  const mlir::SymbolTable &table;
  mlir::ArrayAttr empty;
  // The points that have nodes.
  llvm::DenseMap<PointKey, Node> nodes;
  // Each operand's one sink.
  llvm::DenseMap<mlir::OpOperand *, FlowPoint> sinks;
  // Each node's labels in name order, one uniqued attribute per set.
  std::vector<mlir::ArrayAttr> labels;
};

// The graph and its solver. The build (LabelSites.cpp) adds points and
// edges as the ops declare them; the solve (Labels.cpp) runs the worklist
// and hands the points and their sets to the Solution.
class Graph {
public:
  explicit Graph(const mlir::SymbolTable &table);

  void walk(mlir::Operation *program);
  // The least solution of the edges walked; the graph is spent.
  Solution solve() &&;

private:
  // What a class of the union-find holds; only a root's is current. Every
  // successor and dispatch has been given, or is owed through a queued
  // arrival, every label of `labels`.
  struct Class {
    // Sorted by number.
    llvm::SmallVector<Label, 2> labels;
    llvm::SmallVector<Node, 2> successors;
    llvm::SmallVector<Dispatch, 1> dispatches;
  };

  // Building.
  void add(mlir::Operation *op, const FlowEdges::Edge &edge);
  Node nodeOf(const PointKey &key);
  Node fresh();
  Node find(Node node);
  Label labelId(mlir::FlatSymbolRefAttr label);

  // Edges.
  void flow(mlir::Operation *op, const FlowPoint &from, const FlowPoint &to, Link how);
  void sink(mlir::OpOperand &use, const FlowPoint &to);
  void link(Node from, Node to, Link how);
  void include(Node from, Node to);
  void unify(Node a, Node b);
  void reach(Node to, Label label);
  void expand(mlir::Attribute part, llvm::function_ref<Node()> at, mlir::Type carrier);

  // Solving.
  void arrive(Arrival arrival);
  void fire(Firing firing);
  mlir::ArrayAttr attrOf(llvm::ArrayRef<Label> set) const;

  // The points as they are met, handed over by the solve.
  Solution out;

  // The union-find, by node.
  std::vector<Node> parents;
  std::vector<Class> classes;

  // Labels by number, numbered as met.
  std::vector<mlir::FlatSymbolRefAttr> labelNames;
  llvm::DenseMap<mlir::StringAttr, Label> labelIds;

  // The dispatches, by number; the closure constants already expanded at a
  // point, and the constructor constants already laid out at their
  // anchors.
  std::vector<mlir::CallOpInterface> dispatches;
  llvm::DenseSet<std::pair<mlir::Attribute, Node>> expanded;
  llvm::DenseSet<mlir::Attribute> laid;
  ClosureParts holding;

  OnceWorklist<Work> work;
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
