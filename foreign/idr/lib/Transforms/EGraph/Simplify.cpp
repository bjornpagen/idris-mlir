// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-simplify: one function's e-graph per run, in two rounds at most
// (EGraph.h), and what a skeleton rule and the optimizer read of it.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/Analysis/Solver/Trace.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <memory>

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::egraph {

using detail::Function;
using detail::Kinds;
using detail::Round;

Attribute OperandFacts::constant(Value value) const {
  return function.classOfValue(value).constant;
}

std::optional<ConstantIntRanges> OperandFacts::range(Value value) const {
  return function.classOfValue(value).range;
}

Operation *OperandFacts::origin(Value value) const { return function.originOf(value); }

Cost OperandFacts::cost(Value value) const { return function.costOf(value); }

void CalleeFacts::publish(solver::FunctionId f, identities::Facts given) {
  if (f.index() >= facts.size().value()) {
    IndexVector<solver::FunctionId, identities::Facts> old = std::move(facts);
    facts = IndexVector<solver::FunctionId, identities::Facts>(
        names->size(), [&](solver::FunctionId g) {
          return g.index() < old.size().value() ? std::move(old[g]) : identities::Facts();
        });
  }
  facts[f] = std::move(given);
}

// A callee the editor does not hold yet (a copy its wave made) has no facts
// yet, and neither has one inserted since the table last grew.
std::span<const identities::GivesBack> CalleeFacts::of(FlatSymbolRefAttr callee) const {
  std::optional<solver::FunctionId> f = names->find(callee);
  if (!f || f->index() >= facts.size().value())
    return {};
  return facts[*f];
}

// What one node costs the arena, every table it enters counted: the node,
// a class of its own, its place among the members and the operands, and
// the hash-cons's two slots at half full.
std::uint64_t arenaBytes(std::uint64_t ops) {
  constexpr std::uint64_t perNode = sizeof(detail::Node) + sizeof(detail::Class) +
                                    sizeof(detail::NodeId) + sizeof(detail::ClassId) +
                                    2 * (sizeof(std::optional<detail::NodeId>) +
                                         sizeof(std::optional<detail::ClassId>));
  return std::uint64_t(nodesPerOp()) * ops * perNode;
}

} // namespace idr::egraph

namespace {

// What the rewrites between the two rounds erase: MLIR reports an erasure
// by its op's address alone, so a root an earlier rewrite took away is
// known here, and skipped.
struct Erasures : RewriterBase::Listener {
  void notifyOperationErased(Operation *op) override { erased.insert(op); }
  llvm::SmallPtrSet<Operation *, 8> erased;
};

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  Simplify() = default;
  explicit Simplify(const idr::egraph::CalleeFacts &callees) : callees(&callees) {}

  // The generated kinds' op names, found once per pass instance: which op
  // an Operation * is is the one fact MLIR's open op set leaves to run time.
  LogicalResult initialize(MLIRContext *context) override {
    kinds = std::make_shared<const idr::egraph::Kinds>(idr::egraph::detail::makeKinds(context));
    return success();
  }

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    idr::solver::SolveUnit unit("idr-simplify", fn.getSymName());
    idr::egraph::Function first(fn, *kinds, callees);
    first.build();
    first.extract();
    first.decide(idr::egraph::Round::First);
    idr::footprint::Vector<idr::egraph::Function::Pending> rewrites = first.rewrites();
    if (rewrites.empty()) {
      IRRewriter rewriter(&getContext());
      first.elaborate(rewriter);
      numWork += first.work();
      return;
    }
    numWork += first.work();
    Erasures erasures;
    IRRewriter rewriter(&getContext(), &erasures);
    for (const idr::egraph::Function::Pending &pending : rewrites) {
      if (erasures.erased.contains(pending.root))
        continue;
      rewriter.setInsertionPoint(pending.root);
      idr::egraph::Function::rewriteSkeleton(pending, rewriter);
    }
    idr::egraph::Function second(fn, *kinds, callees);
    second.build();
    second.extract();
    second.decide(idr::egraph::Round::Second);
    IRRewriter writer(&getContext());
    second.elaborate(writer);
    numWork += second.work();
  }

  std::shared_ptr<const idr::egraph::Kinds> kinds;
  const idr::egraph::CalleeFacts *callees = nullptr;
};

} // namespace

// createIdrSimplify() is the generated constructor; this is the
// optimizer's, for its inner pipeline.
std::unique_ptr<Pass> idr::createIdrSimplify(const egraph::CalleeFacts &callees) {
  return std::make_unique<Simplify>(callees);
}
