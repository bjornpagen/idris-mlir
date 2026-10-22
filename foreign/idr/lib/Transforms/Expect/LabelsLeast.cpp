// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// labels-least: the label solve's answer is, at every point, the least set
// the program's statements give it: every label a source of it reaches
// along the edges, the edges of each label a dispatch runs included, and
// no other. Equal to the least sets, the answer is closed (every statement
// holds of it) and least (every label it holds has a derivation). The
// least sets are derived here the plain way, a label at a time along the
// same statements, over the points and labels the reading numbered: an
// oracle that shares with the solve only the reading of the program, and
// costs the points times the labels, so it is for tests.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/Labels.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <concepts>
#include <utility>

using namespace mlir;

namespace idr::expect {

namespace {

using labels::Dispatch;
using labels::Label;
using labels::Link;
using labels::Node;
using labels::PointKey;

// The least sets of the statements, a (point, label) pair at a time: each
// pair enters once, carries its label along the edges from its point, and
// runs it at each dispatch whose callee is that point, whose edges
// `readFiring` states and the derivation takes in as it took the
// program's. A point's labels are kept in the order they reached it: the
// derivation shares no order of labels with the solve, so the two are
// compared as sets.
class Derivation {
public:
  explicit Derivation(const labels::Read &read)
      : read(read), edges(read.points.size()), held(read.points.size()),
        runsAt(read.points.size()) {
    for (auto [d, dispatched] : llvm::enumerate(read.dispatches))
      runsAt[std::to_underlying(dispatched.callee)].push_back(
          Dispatch(static_cast<unsigned>(d)));
  }

  // Takes statements in: each source reaches its point, and each link
  // connects its points, both ways for one set.
  void take(const labels::Statements &stated) {
    for (const labels::Statements::Source &source : stated.sources)
      reach(source.at, source.label);
    for (const labels::Statements::Linked &linked : stated.links) {
      connect(linked.from, linked.to);
      if (linked.how == Link::Unify)
        connect(linked.to, linked.from);
    }
  }

  // Every pair the statements taken in derive, and those of every firing.
  // The work grows as new pairs and firings are reached, so each index runs
  // to its end.
  void derive() {
    std::size_t pair = 0, fired = 0;
    while (pair < work.size() || fired < firings.size()) {
      if (fired < firings.size()) {
        auto [dispatch, label] = firings[fired++];
        labels::Statements owed;
        labels::readFiring(read, dispatch, label, owed);
        take(owed);
        continue;
      }
      auto [point, label] = work[pair++];
      for (unsigned i = 0; i < edges[point].size(); ++i)
        reach(edges[point][i], label);
      for (Dispatch dispatch : runsAt[point])
        firings.emplace_back(dispatch, label);
    }
  }

  // Every point the reading numbered, with what it is and the labels it
  // derives, each once, as their functions' symbols.
  template <std::invocable<const PointKey &, ArrayRef<FlatSymbolRefAttr>> Each>
  void forEachPoint(Each &&each) const {
    for (const auto &[node, key] : read.points.described()) {
      SmallVector<FlatSymbolRefAttr, 4> symbols;
      for (Label label : held[std::to_underlying(node)])
        symbols.push_back(read.points.symbolOf(label));
      each(key, ArrayRef<FlatSymbolRefAttr>(symbols));
    }
  }

private:
  void reach(Node point, Label label) {
    unsigned at = std::to_underlying(point);
    if (work.insert({at, label}))
      held[at].push_back(label);
  }
  // A new edge carries every label its source holds already.
  void connect(Node from, Node to) {
    unsigned at = std::to_underlying(from);
    edges[at].push_back(to);
    for (unsigned i = 0; i < held[at].size(); ++i)
      reach(to, held[at][i]);
  }

  // A (point, label) pair, the unit of the derivation's work.
  using Pair = std::pair<unsigned, Label>;

  const labels::Read &read;
  // By point: where it carries its labels, the labels it holds, and the
  // dispatches whose callee it is. Each is sized by the program, so it is
  // the footprint's, as the solve's own state is.
  footprint::Vector<footprint::Vector<Node>> edges;
  footprint::Vector<footprint::Vector<Label>> held;
  footprint::Vector<footprint::Vector<Dispatch>> runsAt;
  llvm::SetVector<Pair, footprint::Vector<Pair>, footprint::DenseSet<Pair>> work;
  footprint::Vector<labels::Firing> firings;
};

// The point `key` names, for an error: where a value is, the anchor of the
// type every value of its kind holds there, or a function's result.
InFlightDiagnostic failAt(Operation *program, const PointKey &key, StringRef property) {
  return match(
      key,
      [&](Value value) {
        Operation *op = value.getDefiningOp();
        if (!op)
          op = value.getParentBlock()->getParentOp();
        return std::move(fail(value.getLoc(), property) << "a value of " << where(op));
      },
      [&](const FlowAnchor &anchor) {
        InFlightDiagnostic diag = fail(program->getLoc(), property);
        if (std::optional<Type> slot = anchor.slot())
          diag << "the anchor of " << *slot;
        else
          diag << "a capture's anchor";
        return diag;
      },
      [&](const FlowSource::Result &result) {
        return std::move(fail(program->getLoc(), property)
                         << "result " << result.index << " of @"
                         << result.function.getValue());
      });
}

} // namespace

LogicalResult labelsLeast(const Request<Nothing> &request) {
  ModuleOp module = request.module;
  auto program = dyn_cast<ProgramOp>(programOf(module));
  if (!program)
    return fail(module.getLoc(), request.property)
           << "the module holds no idr.program, whose labels the solve finds";
  AnalysisManager analyses = request.analyses.nest(program);
  const idr::Labels &solved = analyses.getAnalysis<idr::Labels>();
  const labels::Read read =
      labels::readProgram(program, analyses.getAnalysis<solver::ProgramGraph>());
  Derivation derivation(read);
  derivation.take(read.statements);
  derivation.derive();
  // Each side as a set: the solve holds its labels in its own order, which
  // the derivation does not share.
  bool held = true;
  derivation.forEachPoint([&](const PointKey &key, ArrayRef<FlatSymbolRefAttr> derived) {
    ArrayAttr found = solved.labelsAt(key);
    llvm::SmallDenseSet<Attribute, 8> least(derived.begin(), derived.end());
    llvm::SmallDenseSet<Attribute, 8> solvedSet(found.begin(), found.end());
    for (Attribute label : found)
      if (!least.contains(label)) {
        failAt(program, key, request.property)
            << " holds " << label << ", which no source reaches";
        held = false;
      }
    for (FlatSymbolRefAttr label : derived)
      if (!solvedSet.contains(label)) {
        failAt(program, key, request.property)
            << " lacks " << label << ", which a source reaches";
        held = false;
      }
  });
  return success(held);
}

} // namespace idr::expect
