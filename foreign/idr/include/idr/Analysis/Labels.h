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
// program (LabelSites.cpp) numbers each point once: every function's
// parameters and results laid out by its label before any statement, each
// other point where a statement first names it. It states, over those
// numbers, where each label starts, which points include or equal which,
// and which calls run the labels a point holds; the solve (Labels.cpp) and
// the check of its answer (idr-expect's labels-least) read the same
// statements. There is no unknown: the world is closed, every op that moves
// a closure declares how, and a set is a finite set of the program's
// functions. A value of any other carrier has no point and holds no label.
//
// A handle becomes a point's number in one place, the points' tables
// (LabelPoints.h), written by the reading and read where a question
// arrives by handle; the solve's waves and firings read numbers alone, and
// so does every table the solve keeps per point.
//
// The solve keeps a set of labels once, however many points hold it: a
// class of points holds the identity of its set, never a copy, so a
// program whose points share a few large sets is solved in time and space
// near the size of those sets, not of the points times their labels.
//
// A label is its function's id in the program graph, its position among
// the program's functions: the one order of labels, in which every set is
// held, answered and made a sum's tags. A name is text for a human, and
// never orders anything here.
//
// A call in tail position gives its caller's results, so the labels its
// callee returns are its caller's: the two functions' result points are one
// set, and a closure a tail call returns needs no conversion after it.
//
// The graph is spent by its solve, which leaves a Solution: the points'
// tables, each point's labels and each operand's sink, read and never
// written from then on.
//
// The solve's work is what its waves read: each class taken, each edge,
// each dispatch, and each label a union, an interning or a dispatch's new
// labels read. Its points, sinks, statements, sets, union-find, waves'
// tables and the solution's tables are the footprint's.
#ifndef IDR_ANALYSIS_LABELS_H
#define IDR_ANALYSIS_LABELS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "idr/Analysis/Solver/Decision.h"
#include "idr/Analysis/Solver/LabelPoints.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Support/Footprint.h"

#include "mlir/Pass/AnalysisManager.h"

#include <cstdint>
#include <optional>
#include <utility>

namespace idr {

// Whether a value of `type` carries labels: a closure or a suspension, at
// any grade. A value of any other type carries none, whatever it holds: an
// anchor holds the labels of its parts.
inline bool carriesLabels(mlir::Type type) {
  return !(Carriers::of(type) & Carriers::labels()).empty();
}

// Which parts of the program's constants hold a closure, each part answered
// once: a closure does, a constructor does when one of its fields does, and
// nothing else does. A constructor is answered after its fields, on an
// explicit stack, so a constant of any depth takes no recursion.
class ClosureParts {
public:
  bool holds(mlir::Attribute part);

private:
  // What an answered part holds; a part that is neither a closure nor a
  // constructor holds nothing, and is never stored.
  bool answer(mlir::Attribute part) const;

  footprint::DenseMap<mlir::Attribute, bool> known;
};

namespace labels {

// A set of labels, interned: equal sets are one SetId, and SetId{0} is the
// empty set.
enum class SetId : std::uint32_t {};
// A dispatch (a call through a value, which runs each label its callee
// holds), by the order the reading met it.
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

// Where a call stands: in tail position its results are its caller's.
enum class Standing : std::uint8_t { Within, Tail };

// What the program states of its labels, over its points: a label starts
// at a point; one point's labels are at another (Include), or two points
// hold one set (Unify). The statements are data, the rules of the solve:
// the solve builds its graph from them, and the check of its answer derives
// the least sets from the same data.
struct Statements {
  struct Source {
    Node at;
    Label label;
  };
  struct Linked {
    Node from, to;
    Link how;
  };
  footprint::Vector<Source> sources;
  footprint::Vector<Linked> links;
};

// A value a dispatch moves, at its position among the call's arguments or
// results, with its link.
struct Moved {
  std::uint32_t position;
  Node node;
  Link how;
};

// A dispatch, read once: the node of its callee, the function it is in,
// where it stands, how many arguments it passes (a label takes them after
// its captures), and what it moves: [firstArgument, firstResult) of the
// reading's moves are its arguments that carry a label, [firstResult, end)
// its results that do. The edges of every label it runs follow from these.
struct Dispatched {
  Node callee;
  Label caller;
  Standing standing;
  std::uint32_t arguments;
  std::uint32_t firstArgument, firstResult, end;
};

// The reading of a program: its points, its sinks, its statements, and
// each dispatch with the moves it states.
struct Read {
  Points points;
  Sinks sinks;
  Statements statements;
  footprint::Vector<Dispatched> dispatches;
  footprint::Vector<Moved> moves;
};

// Reads every edge of `program`, an idr.program, that carries a label, and
// the constants' parts where they are held. A use that moves into two
// points states them one set, and so does a direct call in tail position
// its callee's result points and its caller's.
Read readProgram(mlir::Operation *program, const solver::ProgramGraph &graph);

// States the edges `label` owes at `dispatch`, of `read`, which runs it:
// the call's arguments at the label's parameters after its captures, its
// results at the call's, and, in tail position, the label's result points
// one set with its caller's. Numbers alone.
void readFiring(const Read &read, Dispatch dispatch, Label label, Statements &to);

// Whether every label of `a` is one of `b`'s, both sets of labelsOf, held
// in the solve's one order of labels: one walk along `b`, each label of `a`
// met after the one before, by identity.
bool within(mlir::ArrayAttr a, mlir::ArrayAttr b);

class Graph;

// What the solve leaves: the points' tables, the labels of each point,
// and the one sink of each operand. It is never written once made, so it is
// read from any thread, while the program graph whose labels it holds is
// frozen.
class Solution {
public:
  // The labels at a point; the empty set where no label reaches.
  mlir::ArrayAttr labelsOf(mlir::Value value) const { return labelsAt(points.find(value)); }
  mlir::ArrayAttr labelsOf(const FlowAnchor &anchor) const {
    return labelsAt(points.find(anchor));
  }
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const;
  mlir::ArrayAttr labelsOf(const PointKey &key) const;
  std::optional<FlowPlace> sinkOf(mlir::OpOperand &operand) const { return sinks.of(operand); }
  FuncOp function(mlir::StringAttr label) const {
    return points.function(mlir::FlatSymbolRefAttr::get(label));
  }
  // The position of `label` in `set`, a set of labelsOf: a binary search by
  // the labels' one order; none when the set does not hold it.
  std::optional<unsigned> positionIn(mlir::ArrayAttr set, mlir::FlatSymbolRefAttr label) const;

private:
  friend class Graph;
  Solution(Points points, Sinks sinks, footprint::Vector<mlir::ArrayAttr> labels,
           mlir::ArrayAttr empty);

  mlir::ArrayAttr labelsAt(std::optional<Node> node) const {
    return node ? labels[std::to_underlying(*node)] : empty;
  }

  Points points;
  Sinks sinks;
  // Each point's labels in the labels' order, one uniqued attribute per set.
  footprint::Vector<mlir::ArrayAttr> labels;
  mlir::ArrayAttr empty;
};

} // namespace labels

class Labels : public solver::ReadsAnalyses<Labels, solver::ProgramGraph> {
public:
  Labels(mlir::Operation *program, mlir::AnalysisManager &am);

  // The labels a closure or suspension at a point may be: a uniqued
  // ArrayAttr of FlatSymbolRefAttr in the labels' one order (their
  // functions' order in the program), the empty ArrayAttr where no label
  // reaches. A point whose carrier carries no label holds the empty set.
  // Two equal sets are one attribute. A part of a value is its anchor, the
  // same for every value of its kind.
  mlir::ArrayAttr labelsOf(mlir::Value value) const { return solution.labelsOf(value); }
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const { return solution.labelsOf(point); }
  mlir::ArrayAttr labelsOf(const FlowAnchor &anchor) const { return solution.labelsOf(anchor); }
  mlir::ArrayAttr labelsAt(const labels::PointKey &key) const { return solution.labelsOf(key); }

  // The labels `runner` runs: those of the closure or suspension it
  // carries (an idr.fn.apply's callee, an idr.lazy.force's cell).
  mlir::ArrayAttr runs(RunsLabelsOpInterface runner) const {
    return labelsOf(runner.getLabelCarrier());
  }

  // The one place `operand` moves its value into at its op, or nothing: an
  // operand of a carrier that carries no label, and the callee and the
  // arguments of a dispatch, which move per label.
  std::optional<FlowPlace> sinkOf(mlir::OpOperand &operand) const {
    return solution.sinkOf(operand);
  }

  // The function of `label`, through the program graph.
  FuncOp function(mlir::StringAttr label) const { return solution.function(label); }

  // The position of `label` in `set`, a set of labelsOf, which is its tag
  // in the sum of that set; none when the set does not hold it.
  std::optional<unsigned> positionIn(mlir::ArrayAttr set, mlir::FlatSymbolRefAttr label) const {
    return solution.positionIn(set, label);
  }

  // What the solve read, the work of the pass that computes the labels.
  std::uint64_t work() const { return spent.steps(); }

private:
  // Before the solution, which its solve counts into as it is made.
  solver::Work spent;
  labels::Solution solution;
};

} // namespace idr

#endif // IDR_ANALYSIS_LABELS_H
