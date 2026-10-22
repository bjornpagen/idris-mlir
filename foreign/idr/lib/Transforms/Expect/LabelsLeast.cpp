// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// labels-least: the label solve's answer is, at every point, the least set
// the program's statements give it: every label a source of it reaches
// along the edges, the edges of each label a dispatch runs included, and
// no other. Equal to the least sets, the answer is closed (every statement
// holds of it) and least (every label it holds has a derivation). The
// least sets are derived here the plain way, a label at a time along the
// same statements: an oracle that shares with the solve only the reading
// of the program, and costs the points times the labels, so it is for
// tests.

#include "Checks.h"

#include "idr/Analysis/Labels.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <concepts>
#include <vector>

using namespace mlir;

namespace idr::expect {

namespace {

using labels::Link;
using labels::PointKey;

// The least sets of the statements, a (point, label) pair at a time: each
// pair enters once, carries its label along the edges from its point, and
// runs it at each dispatch there, whose edges `readFiring` states for the
// place the call stands and the derivation takes in as it took the
// program's. A label is kept by its symbol, in the order it reached its
// point: the derivation shares no order of labels with the solve, so the
// two are compared as sets.
class Derivation {
public:
  explicit Derivation(const SymbolTable &table) : table(table) {}

  // Takes statements in: each source reaches its point, each link connects
  // its points (both ways for one set), and each dispatch runs the labels
  // its callee holds already and every label that reaches it later.
  void take(const labels::Statements &stated) {
    for (const labels::Statements::Source &source : stated.sources)
      reach(pointOf(source.at), source.label);
    for (const labels::Statements::Linked &linked : stated.links) {
      unsigned a = pointOf(linked.from), b = pointOf(linked.to);
      connect(a, b);
      if (linked.how == Link::Unify)
        connect(b, a);
    }
    for (const labels::Statements::Dispatched &dispatched : stated.dispatches) {
      unsigned callee = pointOf(dispatched.callee);
      calls[callee].push_back({dispatched.call, dispatched.standing});
      for (FlatSymbolRefAttr label : held[callee])
        firings.push_back({{dispatched.call, dispatched.standing}, label});
    }
  }

  // Every pair the statements taken in derive, and those of every firing.
  // The work grows as new pairs and firings are reached, so each index runs
  // to its end.
  void derive() {
    std::size_t pair = 0, fired = 0;
    while (pair < work.size() || fired < firings.size()) {
      if (fired < firings.size()) {
        auto [run, label] = firings[fired++];
        labels::Statements owed;
        labels::readFiring(table, run.call, run.standing, label, owed);
        take(owed);
        continue;
      }
      auto [point, label] = work[pair++];
      for (unsigned i = 0; i < edges[point].size(); ++i)
        reach(edges[point][i], label);
      for (const Run &run : calls[point])
        firings.push_back({run, label});
    }
  }

  // Every point stated, with its key and the labels it derives, each once,
  // in the order they reached it.
  template <std::invocable<const PointKey &, ArrayRef<FlatSymbolRefAttr>> Each>
  void forEachPoint(Each &&each) const {
    for (auto [point, key] : llvm::enumerate(keys))
      each(key, ArrayRef<FlatSymbolRefAttr>(held[point]));
  }

private:
  // A dispatch, and where it stands: what its firings owe depends on both.
  struct Run {
    CallOpInterface call;
    labels::Standing standing;
  };

  // The number of a point, minted where the statements first name it.
  unsigned pointOf(const PointKey &key) {
    auto [it, made] = index.try_emplace(key, static_cast<unsigned>(keys.size()));
    if (made) {
      keys.push_back(key);
      edges.emplace_back();
      held.emplace_back();
      calls.emplace_back();
    }
    return it->second;
  }
  void reach(unsigned point, FlatSymbolRefAttr label) {
    if (work.insert({point, label}))
      held[point].push_back(label);
  }
  // A new edge carries every label its source holds already.
  void connect(unsigned from, unsigned to) {
    edges[from].push_back(to);
    for (unsigned i = 0; i < held[from].size(); ++i)
      reach(to, held[from][i]);
  }

  const SymbolTable &table;
  llvm::DenseMap<PointKey, unsigned> index;
  std::vector<PointKey> keys;
  std::vector<SmallVector<unsigned, 2>> edges;
  std::vector<SmallVector<FlatSymbolRefAttr, 2>> held;
  std::vector<SmallVector<Run, 1>> calls;
  llvm::SetVector<std::pair<unsigned, FlatSymbolRefAttr>> work;
  std::vector<std::pair<Run, FlatSymbolRefAttr>> firings;
};

// The point `key` names, for an error: where a value is, a function's
// result, or the anchor of the type every value of its kind holds there.
InFlightDiagnostic failAt(Operation *program, const PointKey &key, StringRef property) {
  return std::visit(
      llvm::makeVisitor(
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
          [&](const labels::ResultKey &result) {
            return std::move(fail(program->getLoc(), property)
                             << "result " << result.second << " of @" << result.first.getValue());
          }),
      key);
}

} // namespace

LogicalResult labelsLeast(const Request<Nothing> &request) {
  ModuleOp module = request.module;
  auto program = dyn_cast<ProgramOp>(programOf(module));
  if (!program)
    return fail(module.getLoc(), request.property)
           << "the module holds no idr.program, whose labels the solve finds";
  SymbolTable &table = symbolsOf(module, request.analyses);
  const idr::Labels &solved = request.analyses.nest(program).getAnalysis<idr::Labels>();
  labels::Statements stated;
  llvm::DenseMap<OpOperand *, FlowPoint> sinks;
  labels::readProgram(program, table, stated, sinks);
  Derivation derivation(table);
  derivation.take(stated);
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
