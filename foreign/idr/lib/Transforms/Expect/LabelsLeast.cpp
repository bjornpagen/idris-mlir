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

#include "idr/Analysis/Labels.h"
#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

using labels::Link;
using labels::PointKey;

// The least sets of the statements, a (point, label) pair at a time: each
// pair enters once, carries its label along the edges from its point, and
// runs it at each dispatch there, whose edges are new edges.
class Derivation final : public labels::Statements {
public:
  explicit Derivation(const SymbolTable &table) : table(table) {}

  void source(const PointKey &at, FlatSymbolRefAttr label) override { reach(pointOf(at), label); }
  void link(const PointKey &from, const PointKey &to, Link how) override {
    unsigned a = pointOf(from), b = pointOf(to);
    connect(a, b);
    if (how == Link::Unify)
      connect(b, a);
  }
  void dispatch(const PointKey &callee, CallOpInterface call) override {
    calls[pointOf(callee)].push_back(call);
  }

  // Once the program is read: every pair it derives.
  void derive() {
    while (std::optional<std::pair<unsigned, FlatSymbolRefAttr>> pair = work.pop()) {
      auto [point, label] = *pair;
      for (unsigned i = 0; i < edges[point].size(); ++i)
        reach(edges[point][i], label);
      for (CallOpInterface call : calls.lookup(point))
        labels::readFiring(table, call, label, *this);
    }
  }

  // Every point stated, with its key and the labels it derives, in name
  // order.
  template <typename Fn> void forEachPoint(Fn &&each) const {
    for (auto [point, key] : llvm::enumerate(keys)) {
      SmallVector<Attribute> derived(held[point].begin(), held[point].end());
      llvm::sort(derived, [](Attribute a, Attribute b) {
        return cast<FlatSymbolRefAttr>(a).getValue() < cast<FlatSymbolRefAttr>(b).getValue();
      });
      each(key, derived);
    }
  }

private:
  unsigned pointOf(const PointKey &key) {
    auto [it, made] = index.try_emplace(key, static_cast<unsigned>(keys.size()));
    if (made) {
      keys.push_back(key);
      edges.emplace_back();
      held.emplace_back();
    }
    return it->second;
  }
  void reach(unsigned point, FlatSymbolRefAttr label) {
    if (work.push({point, label}))
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
  llvm::DenseMap<unsigned, SmallVector<CallOpInterface, 1>> calls;
  OnceWorklist<std::pair<unsigned, FlatSymbolRefAttr>> work;
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
  Derivation derivation(table);
  llvm::DenseMap<OpOperand *, FlowPoint> sinks;
  labels::readProgram(program, table, derivation, sinks);
  derivation.derive();
  bool held = true;
  derivation.forEachPoint([&](const PointKey &key, ArrayRef<Attribute> derived) {
    ArrayAttr found = solved.labelsAt(key);
    ArrayAttr least = ArrayAttr::get(program.getContext(), derived);
    if (found == least)
      return;
    held = false;
    for (Attribute label : found)
      if (!llvm::is_contained(derived, label))
        failAt(program, key, request.property)
            << " holds " << label << ", which no source reaches";
    for (Attribute label : derived)
      if (!llvm::is_contained(found, label))
        failAt(program, key, request.property)
            << " lacks " << label << ", which a source reaches";
  });
  return success(held);
}

} // namespace idr::expect
