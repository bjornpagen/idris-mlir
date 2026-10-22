// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Leaf inlining, an inner pass of idr-optimize, and the verdict of the
// inline phase.
//
// Inlining never clears what Idris proved of the caller: a callee inlined
// from another component adds no cycle through its caller, and inside one
// a beta step calls the recursion, never itself, so every loop through the
// caller ran through it before. What the callee may do the caller's row
// already covered, since a call's row is its callee's; the writer derives
// the caller's own once its component is final. A call the inlined body
// holds keeps its tail fact only where the call it replaced was in tail
// position: the dialect's inliner interface composes them.
//
// A callee that ends in ub.unreachable never returns: inlining leaves the
// rest of the call's block unreachable, which goes once every call the
// step took is inlined or kept, since a call taken before may sit in it.

#include "idr/Transforms/Inline.h"

#include "idr/Analysis/Inline.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRINLINELEAVES
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::inlining {

namespace {

// idr-optimize inlines one call; the unit is the call.
struct InlineAction : support::TaggedAction<InlineAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-inline";
};

} // namespace

Body bodyOf(FuncOp fn) {
  Body body{0, Calls::None};
  fn.getBody().walk([&](Operation *op) {
    ++body.size;
    if (isa<CallOp>(op))
      body.calls = Calls::Some;
  });
  return body;
}

Verdict verdictOf(const solver::ProgramGraph &graph, solver::FunctionId caller,
                  solver::FunctionId callee, const Body &body, std::optional<CopyKind> copy) {
  if (caller == callee)
    return Keep{Reason::Cycle};
  if (copy == CopyKind::Step)
    return Keep{Reason::Step};
  if (graph.sccOf(caller) == graph.sccOf(callee) && copy != CopyKind::Beta)
    return Keep{Reason::Cycle};
  if (body.calls == Calls::None && body.size <= kLeafSize)
    return Leaf{};
  return Weighed{body.size, graph.callSites(callee)};
}

Profitability::Profitability(const solver::ProgramGraph &graph) : graph(graph) {}

bool Profitability::operator()(const Inliner::ResolvedCall &resolved) {
  auto caller = cast<FuncOp>(resolved.sourceNode->getCallableRegion()->getParentOp());
  auto callee = cast<FuncOp>(resolved.targetNode->getCallableRegion()->getParentOp());
  solver::FunctionId from = graph.id(FlatSymbolRefAttr::get(caller.getSymNameAttr()));
  solver::FunctionId to = graph.id(FlatSymbolRefAttr::get(callee.getSymNameAttr()));
  auto sizeOf = [&](solver::FunctionId fn, FuncOp op) -> std::int64_t & {
    auto [at, fresh] = sizes.try_emplace(fn, 0);
    if (fresh)
      at->second = bodyOf(op).size;
    return at->second;
  };
  auto [body, fresh] = bodies.try_emplace(to, Body{});
  if (fresh)
    body->second = bodyOf(callee);
  bool profitable = idr::match(
      verdictOf(graph, from, to, body->second, callee.getCopy()), [](Keep) { return false; },
      [](Leaf) { return true; },
      [](const Weighed &weighed) {
        return (static_cast<std::int64_t>(weighed.calls) - 1) * (weighed.size - kSmall) <= kProduct;
      });
  if (!profitable)
    return false;
  std::int64_t &size = sizeOf(from, caller);
  if (!fitsCap(size, body->second.size)) {
    ++numCapped;
    return false;
  }
  size += body->second.size - 1;
  ++numInlined;
  return true;
}

namespace {

struct InlineLeaves : impl::IdrInlineLeavesBase<InlineLeaves> {
  InlineLeaves(optimize::Schedule &schedule, Pass::Statistic &numInlined)
      : schedule(schedule), numInlined(numInlined) {}

  // Each call the function holds when the step starts whose callee is
  // final and a leaf, in walk order, while the caller stays within the
  // cap. A body brought in calls nothing, so the step brings no call.
  void runOnOperation() override {
    FuncOp caller = getOperation();
    SmallVector<CallOp> calls;
    caller.getBody().walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
    std::int64_t size = bodyOf(caller).size;
    InlinerInterface interface(caller.getContext());
    InlinerConfig config;
    unsigned inlined = 0;
    for (CallOp call : calls) {
      std::optional<solver::FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
      if (!callee)
        continue;
      std::optional<optimize::Readable> known = schedule.final(*callee);
      if (!known)
        continue;
      const Body &body = schedule.summaryOf(*callee)->body;
      if (body.calls != Calls::None || body.size > kLeafSize || !fitsCap(size, body.size))
        continue;
      FuncOp fn = known->fn;
      (void)support::perform<InlineAction>(call, [&] {
        if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                              /*shouldCloneInlinedRegion=*/true)))
          return;
        call.erase();
        size += body.size - 1;
        ++inlined;
      });
    }
    numInlined += inlined;
    schedule.noteLeaves(schedule.graph.id(FlatSymbolRefAttr::get(caller.getSymNameAttr())), inlined);
    if (inlined == 0)
      return markAllAnalysesPreserved();
    IRRewriter rewriter(caller.getContext());
    (void)eraseUnreachableBlocks(rewriter, caller.getBody());
  }

  optimize::Schedule &schedule;
  Pass::Statistic &numInlined;
};

} // namespace

std::unique_ptr<Pass> createInlineLeaves(optimize::Schedule &schedule, Pass::Statistic &inlined) {
  return std::make_unique<InlineLeaves>(schedule, inlined);
}

} // namespace idr::inlining
