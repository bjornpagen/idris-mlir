// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve's points and sinks (Labels.h), each numbered once by the
// reading of the program. A function's parameters and results are laid out
// by its label before any statement is read, a parameter's node also its
// entry argument's; a value or an anchor gets its node where a statement
// first names it, and an operand its sink where it first moves a label.
// These tables are the one place a handle becomes a number: the reading
// writes them, an answer reads them, and the solve between reads numbers
// alone. Every table here is the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_LABELPOINTS_H
#define IDR_ANALYSIS_SOLVER_LABELPOINTS_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include <cstdint>
#include <optional>
#include <utility>
#include <variant>

namespace idr::labels {

// A point, numbered once by the reading.
enum class Node : unsigned {};
// A label, by its function's id in the program graph: a set's members in
// that order are its labels in the order of its ArrayAttr and of its sum's
// tags.
enum class Label : std::uint32_t {};
// An operand that moves a label, by the order the reading met it.
enum class Sink : unsigned {};

// What a point is, for a reader that names it to a human or asks the solve
// about it by what it is: a value (a function's parameter is its entry
// argument), an anchor, or a function's result.
using PointKey = std::variant<mlir::Value, FlowAnchor, FlowSource::Result>;

// An anchor as a key of the points' table: its own hash and equality, and
// as the two keys a table reserves, the elements of the two types
// DenseMap reserves, which no shaped value has.
struct AnchorKeys {
  static FlowAnchor getEmptyKey() {
    return FlowAnchor::elementsOf(llvm::DenseMapInfo<mlir::Type>::getEmptyKey());
  }
  static FlowAnchor getTombstoneKey() {
    return FlowAnchor::elementsOf(llvm::DenseMapInfo<mlir::Type>::getTombstoneKey());
  }
  static unsigned getHashValue(const FlowAnchor &anchor) {
    return llvm::DenseMapInfo<FlowAnchor>::getHashValue(anchor);
  }
  static bool isEqual(const FlowAnchor &a, const FlowAnchor &b) { return a == b; }
};

// The program's points. Every function's parameters and results are laid
// out by its label when the points are made, a parameter's node also its
// entry argument's; a value or an anchor gets its node where the reading
// first names it, and keeps it.
class Points {
public:
  explicit Points(const solver::ProgramGraph &graph);

  // The label of the function `symbol` names, which the verifier proved
  // one, read through the graph's one table of names.
  Label labelOf(mlir::FlatSymbolRefAttr symbol) const { return Label(graph->id(symbol).index()); }
  Label labelOf(idr::FuncOp fn) const { return Label(graph->id(fn).index()); }
  mlir::FlatSymbolRefAttr symbolOf(Label label) const { return symbols[std::to_underlying(label)]; }
  idr::FuncOp function(mlir::FlatSymbolRefAttr symbol) const {
    return graph->op(graph->id(symbol));
  }

  Node parameter(Label label, unsigned index) const {
    return Node(laid[std::to_underlying(label)].parameters + index);
  }
  Node result(Label label, unsigned index) const {
    return Node(laid[std::to_underlying(label)].results + index);
  }
  unsigned parameters(Label label) const {
    const Laid &at = laid[std::to_underlying(label)];
    return at.results - at.parameters;
  }

  // The node of a value or an anchor, made where the reading first names it.
  Node of(mlir::Value value);
  Node of(const FlowAnchor &anchor);
  // The node of a value or an anchor; none where no statement named it.
  std::optional<Node> find(mlir::Value value) const;
  std::optional<Node> find(const FlowAnchor &anchor) const;

  // How many points there are: every node is below this.
  std::uint32_t size() const { return count; }

  // Every point with what it is, in node order, for a reader that names
  // points to a human; nothing the solve reads.
  footprint::Vector<std::pair<Node, PointKey>> described() const;

private:
  // A function's points: its parameters from `parameters`, its results
  // from `results`, up to `end`.
  struct Laid {
    std::uint32_t parameters, results, end;
  };

  const solver::ProgramGraph *graph;
  // By label: each function's symbol, and where its points lie.
  footprint::Vector<mlir::FlatSymbolRefAttr> symbols;
  footprint::Vector<Laid> laid;
  // The one place a value or an anchor becomes its node.
  footprint::DenseMap<mlir::Value, Node> values;
  footprint::DenseMap<FlowAnchor, Node, AnchorKeys> anchors;
  std::uint32_t count = 0;
};

// The node of a source as the reading states it: a use's value, a value or
// a part's anchor, through `known`, with which the reading makes a node
// and an answer finds one; a parameter or a result by its function's label.
template <class Known>
auto nodeOf(const Points &points, const FlowSource &point, Known &&known) {
  using Answer = decltype(known(mlir::Value()));
  return match(
      point.at, [&](FlowSource::Taken taken) -> Answer { return known(taken.use->get()); },
      [&](FlowSource::Whole whole) -> Answer { return known(whole.value); },
      [&](const FlowSource::Part &part) -> Answer { return known(part.anchor); },
      [&](FlowSource::Parameter param) -> Answer {
        return points.parameter(points.labelOf(param.function), param.index);
      },
      [&](FlowSource::Result result) -> Answer {
        return points.result(points.labelOf(result.function), result.index);
      });
}

// The node of a place, the same way: a value or a part's anchor through
// `known`, a parameter or a result by its function's label.
template <class Known>
auto nodeOf(const Points &points, const FlowPlace &place, Known &&known) {
  using Answer = decltype(known(mlir::Value()));
  return match(
      place.at, [&](FlowSource::Whole whole) -> Answer { return known(whole.value); },
      [&](const FlowPlace::Part &part) -> Answer { return known(part.anchor); },
      [&](FlowSource::Parameter param) -> Answer {
        return points.parameter(points.labelOf(param.function), param.index);
      },
      [&](FlowSource::Result result) -> Answer {
        return points.result(points.labelOf(result.function), result.index);
      });
}

// Each operand that moves a label at its op, and the one place it moves its
// value into there, by the order the reading met it.
class Sinks {
public:
  // The place `use` moves its value into; none where it moves no label.
  std::optional<FlowPlace> of(mlir::OpOperand &use) const;
  // `use` moves its value into `target`: the sink it had already, which the
  // reading joins to `target`; none the first time, `target` its sink.
  std::optional<FlowPlace> meet(mlir::OpOperand &use, const FlowPlace &target);

private:
  // The one place an operand becomes its sink.
  footprint::DenseMap<mlir::OpOperand *, Sink> index;
  footprint::Vector<FlowPlace> targets;
};

} // namespace idr::labels

#endif // IDR_ANALYSIS_SOLVER_LABELPOINTS_H
