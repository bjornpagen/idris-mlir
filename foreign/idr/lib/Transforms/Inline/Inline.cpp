// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline step. Every callee it reads is final, so its body is the one
// every caller copies and no worker writes it; the caller is the one
// function this step writes. The calls are taken once, before the first
// inline, so a body copied in brings calls the step does not see: those
// the callee kept, which the rule already weighed, and those its cleanup
// exposes, which the next step of the caller's loop sees.
//
// A callee that ends in ub.unreachable never returns: the inliner keeps
// its terminator and leaves the rest of the call's block unreachable, a
// second block of the caller. It goes once, after every call the step took
// is inlined or kept: a call taken before may sit in it, inlined there to
// no effect, and an erase between two inlines would leave that call freed.

#include "idr/Transforms/Inline.h"

#include "idr/Analysis/Inline.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Visitors.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <variant>

using namespace mlir;

namespace {

// idr-optimize's inline step inlines one call; the unit is the call.
struct InlineAction : idr::support::TaggedAction<InlineAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-inline";
};

} // namespace

idr::inlining::Step
idr::inlining::inlineCalls(FuncOp caller,
                           llvm::function_ref<optimize::Callee(StringAttr)> callee) {
  Step step;
  SmallVector<CallOp> calls;
  caller.getBody().walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
  if (calls.empty())
    return step;
  int64_t size = inlineSize(caller);
  InlinerInterface interface(caller.getContext());
  InlinerConfig config;
  for (CallOp call : calls) {
    optimize::Callee answer = callee(call.getCalleeAttr().getAttr());
    // A callee that is not final is a member of the caller's own
    // component, or one it waits on: never inlined, and never read.
    const auto *known = std::get_if<optimize::Final>(&answer);
    if (!known)
      continue;
    FuncOp fn = known->fn;
    const Facts &facts = known->summary.facts;
    if (!facts.inlines)
      continue;
    if (!fitsCap(size, facts.size)) {
      ++step.capped;
      continue;
    }
    (void)idr::support::perform<InlineAction>(call, [&] {
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/true)))
        return;
      caller.absorb(fn);
      call.erase();
      size += facts.size - 1;
      ++step.inlined;
    });
  }
  // Only an inline leaves a block unreachable.
  if (step.inlined != 0) {
    IRRewriter rewriter(caller.getContext());
    (void)eraseUnreachableBlocks(rewriter, caller.getBody());
  }
  return step;
}
