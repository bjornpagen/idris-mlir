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
// union-find; a class holds the set of labels its points may be, the set
// it has sent on, the classes its labels flow into, and the dispatches its
// labels run. A set is a sorted array of label numbers, made once per
// distinct content; only a class's own sets are made, and the labels sent
// on are the difference between them, which is never kept. There is no
// unknown: the world is closed, every op that moves a closure declares
// how, and a set is a finite set of the program's functions. A value of any
// other carrier has no node and holds no label.
//
// The analysis changes nothing, and nothing in it is filled on first ask
// but each set's attribute.
#ifndef IDR_ANALYSIS_LABELS_H
#define IDR_ANALYSIS_LABELS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/Allocator.h"

#include <cstdint>
#include <optional>
#include <tuple>
#include <vector>

namespace idr {

// Whether a value of `type` carries labels: a closure or a suspension, at
// any grade. A value of any other type carries none, whatever it holds: an
// anchor holds the labels of its parts.
inline bool carriesLabels(mlir::Type type) {
  return !(Carriers::of(type) & Carriers::labels()).empty();
}

// The index in its constructor of field `i` of a run's cell, which holds
// every field but the spine.
inline unsigned cellField(unsigned i, unsigned spine) { return i < spine ? i : i + 1; }

// Calls `visit(field, index)` for each field of `con` with its index in the
// constructor: a plain con's fields, or a run's cells, each without its
// spine field, which is the next cell, and then its tail, which fills the
// last cell's spine. A run is walked by its cells, never through its spine,
// which builds the rest of the run at each step.
inline void eachField(ConAttr con, llvm::function_ref<void(mlir::Attribute, unsigned)> visit) {
  if (!con.isRun()) {
    for (auto [i, field] : llvm::enumerate(con.getFields()))
      visit(field, static_cast<unsigned>(i));
    return;
  }
  unsigned spine = con.getSpine();
  for (mlir::ArrayAttr cell : con.getRunCells())
    for (auto [i, field] : llvm::enumerate(cell))
      visit(field, cellField(static_cast<unsigned>(i), spine));
  visit(con.getTail(), spine);
}

namespace labels {

// A node of the graph: one per point.
using Node = unsigned;
// A set of labels, by its number among the distinct sets; 0 is the empty
// set.
using SetId = unsigned;
// A label, by its number, given when it is first met.
using Label = std::uint32_t;

// A dispatch: a call through a value, which runs each label its callee
// holds. `handled` keeps a label's edges from being added twice.
struct Dispatch {
  mlir::CallOpInterface call;
  llvm::DenseSet<Label> handled;
};

// What a class of the union-find holds; only a root's is current. Every
// successor and dispatch has been given `sent` at least, so the class owes
// them `set` less `sent`, and is queued exactly while it owes something.
struct Class {
  SetId set = 0;
  SetId sent = 0;
  bool queued = false;
  llvm::SmallVector<Node, 2> successors;
  llvm::SmallVector<unsigned, 1> dispatches;
};

// The graph and its solver. The build (LabelSites.cpp) adds points and
// edges as the ops declare them; the solver (Labels.cpp) runs the worklist
// and answers.
class Graph {
public:
  explicit Graph(mlir::SymbolTable &table)
      : table(table), context(table.getOp()->getContext()) {
    sets.push_back({});
  }

  // Building.
  void add(mlir::Operation *op, const FlowEdges::Edge &edge);
  void walk(mlir::Operation *program);

  // Solving, then freezing: every path compressed and every set's
  // attribute made, so the answers below read and never write, from any
  // thread.
  void solve();

  // Answers.
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const;
  mlir::ArrayAttr labelsOf(const FlowAnchor &anchor) const;
  mlir::ArrayAttr attrOf(SetId set) const;
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const;
  FuncOp function(mlir::StringAttr label) const { return table.lookup<FuncOp>(label); }

private:
  // Points.
  std::optional<Node> lookup(const FlowPoint &point) const;
  std::optional<Node> lookup(const FlowAnchor &anchor) const;
  Node nodeOf(const FlowPoint &point);
  Node nodeOf(const FlowAnchor &anchor);
  Node fresh();
  Node find(Node node) const;

  // Labels and sets.
  void freeze();
  Label labelId(mlir::FlatSymbolRefAttr label);
  SetId intern(llvm::ArrayRef<Label> ids);

  // Edges.
  void flow(mlir::Operation *op, const FlowPoint &from, const FlowPoint &to, bool lazy);
  void sink(mlir::OpOperand &use, const FlowPoint &to);
  void link(Node from, Node to, bool lazy);
  void include(Node from, Node to);
  void unify(Node a, Node b);
  void addLabels(Node to, llvm::ArrayRef<Label> labels);
  void queue(Node root);
  void fire(unsigned dispatch, llvm::ArrayRef<Label> labels);
  void expand(mlir::Attribute part, llvm::function_ref<Node()> at, mlir::Type carrier);
  bool holdsClosure(mlir::Attribute part);

  mlir::SymbolTable &table;
  mlir::MLIRContext *context;

  // The union-find, by node. Path compression writes only while solving;
  // frozen, every node names its root.
  mutable std::vector<Node> parents;
  std::vector<Class> classes;

  // The points that have nodes.
  llvm::DenseMap<mlir::Value, Node> values;
  llvm::DenseMap<std::pair<mlir::StringAttr, unsigned>, Node> results;
  llvm::DenseMap<std::tuple<unsigned, mlir::Type, unsigned, unsigned>, Node> anchors;

  // Labels by number, numbered as met; a set is sorted by number, and its
  // attribute by name.
  std::vector<mlir::FlatSymbolRefAttr> labelNames;
  llvm::DenseMap<mlir::StringAttr, Label> labelIds;
  llvm::BumpPtrAllocator storage;
  std::vector<llvm::ArrayRef<Label>> sets;
  llvm::DenseMap<llvm::ArrayRef<Label>, SetId> setIds;
  llvm::DenseMap<SetId, mlir::ArrayAttr> attrs;

  // Each operand's one sink, the dispatches, the closure constants already
  // expanded at a point, and the constructor constants already laid out at
  // their anchors.
  llvm::DenseMap<mlir::OpOperand *, FlowPoint> sinks;
  std::vector<Dispatch> dispatches;
  llvm::DenseSet<std::pair<mlir::Attribute, Node>> expanded;
  llvm::DenseSet<mlir::Attribute> laid;
  // Whether each part of the program's constants holds a closure, each part
  // answered once.
  llvm::DenseMap<mlir::Attribute, bool> holding;

  std::vector<Node> worklist;
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
  mlir::ArrayAttr labelsOf(mlir::Value value) const;
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const;
  mlir::ArrayAttr labelsOf(const FlowAnchor &anchor) const;

  // The labels `op` runs: an idr.apply those of its callee, an idr.force
  // those of its cell; the empty set for any other op.
  mlir::ArrayAttr runs(mlir::Operation *op) const;

  // The one point `operand` moves its value into at its op, or nothing: an
  // operand of a carrier that carries no label, and the callee and the
  // arguments of a dispatch, which move per label.
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const {
    return graph.sinkOf(operand);
  }

  // The function of `label`, from the program's table.
  FuncOp function(mlir::StringAttr label) const { return graph.function(label); }

private:
  labels::Graph graph;
};

} // namespace idr

#endif // IDR_ANALYSIS_LABELS_H
