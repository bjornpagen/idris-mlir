// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline step. Every callee it reads is final, so its body is the one
// every caller copies and no worker writes it, or a member of the caller's
// own component, which only the component's turn, this one, writes; the
// caller is the one function this step writes. The calls are taken once, before the first
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
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/Matchers.h"
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

// Whether `param`, a parameter of a callee, is taken apart by a match:
// its own scrutinee, or through the grades on the way to one.
bool dispatched(Value param) {
  for (Operation *user : param.getUsers()) {
    if (auto match = dyn_cast<idr::MatchOp>(user); match && match.getScrutinee() == param)
      return true;
    if (isa<idr::LinUseOp, idr::LinEnterOp>(user) && dispatched(user->getResult(0)))
      return true;
  }
  return false;
}

// Whether every call in `fn` of a function not final (a member of the
// component, or one it waits on) sits in a case of a match on `param`
// other than `tag`'s.
bool callsOnlyBeside(idr::FuncOp fn, Value param, idr::Tag tag,
                     llvm::function_ref<idr::optimize::Callee(StringAttr)> callee) {
  return !fn.getBody()
              .walk([&](idr::CallOp inner) {
                if (std::holds_alternative<idr::optimize::Final>(
                        callee(inner.getCalleeAttr().getAttr())))
                  return WalkResult::advance();
                for (Region *region = inner->getParentRegion(); region != &fn.getBody();
                     region = region->getParentOp()->getParentRegion()) {
                  auto match = dyn_cast<idr::MatchOp>(region->getParentOp());
                  if (!match || idr::throughLinear(match.getScrutinee()) != param)
                    continue;
                  std::optional<idr::Tag> known = match.knownTag(*region);
                  if (known && *known != tag)
                    return WalkResult::advance();
                }
                return WalkResult::interrupt();
              })
              .wasInterrupted();
}

// Whether inlining `call` of `fn`, a member of the caller's own component,
// is beta reduction: at a parameter `fn` dispatches on, the call passes a
// closure or suspension the caller built for it alone (or a constant one),
// of a label whose function is final, so of no function of the recursion,
// and every call `fn` makes of a member is in another case of a match on
// that parameter. Inlined, each such match takes the label's case, and the
// inline leaves no call of the component: it cannot unroll the recursion,
// which the members' rule against inlining one another is for.
bool betaReduces(idr::CallOp call, idr::FuncOp fn,
                 llvm::function_ref<idr::optimize::Callee(StringAttr)> callee) {
  for (auto [arg, param] : llvm::zip_equal(call.getArgs(), fn.getArguments())) {
    idr::DataType data = idr::dataTypeOf(arg.getType());
    if (!data || !(data.isClosures() || data.isMemo()) || !dispatched(param))
      continue;
    Value made = idr::throughLinear(arg);
    std::optional<idr::Tag> tag;
    idr::ConAttr constant;
    if (auto con = made.getDefiningOp<idr::ConOp>(); con && arg.hasOneUse() && made.hasOneUse())
      tag = con.getTag();
    else if (matchPattern(made, m_Constant(&constant)))
      tag = constant.getTag();
    if (!tag)
      continue;
    const auto *label = std::get_if<idr::role::Label>(&data.getCtor(*tag).role);
    if (label && std::holds_alternative<idr::optimize::Final>(callee(label->fn.getAttr())) &&
        callsOnlyBeside(fn, param, *tag, callee))
      return true;
  }
  return false;
}

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
    // component, or one it waits on: never inlined, and never read, but
    // for a member of the component the call applies to a closure of no
    // member's (betaReduces), read as its turn left it.
    FuncOp fn;
    int64_t calleeSize = 0;
    if (const auto *known = std::get_if<optimize::Final>(&answer)) {
      if (!known->summary.facts.inlines)
        continue;
      fn = known->fn;
      calleeSize = known->summary.facts.size;
    } else if (const auto *sibling = std::get_if<optimize::Sibling>(&answer)) {
      if (sibling->fn == caller || !betaReduces(call, sibling->fn, callee))
        continue;
      fn = sibling->fn;
      calleeSize = inlineSize(fn);
    } else {
      continue;
    }
    if (!fitsCap(size, calleeSize)) {
      ++step.capped;
      continue;
    }
    (void)idr::support::perform<InlineAction>(call, [&] {
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/true)))
        return;
      caller.absorb(fn);
      call.erase();
      size += calleeSize - 1;
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
