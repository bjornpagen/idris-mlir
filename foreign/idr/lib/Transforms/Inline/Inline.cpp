// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline step. Every callee it reads is final, so its body is the one
// every caller copies and no worker writes it; the caller is the one
// function this step writes. The calls are taken once, before the first
// inline, so a body copied in brings calls the step does not see: those
// the callee kept, which the rule already weighed, and those its cleanup
// exposes, which the next step of the caller's loop sees.

#include "idr/Transforms/Inline.h"

#include "idr/Analysis/Inline.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/Visitors.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

bool idr::inlining::fitsRegion(InlinerInterface &interface, CallOp call, FuncOp callee) {
  Region &body = callee.getBody();
  bool needsBlocks =
      llvm::hasNItemsOrMore(body, /*N=*/2) || !interface.allowSingleBlockOptimization(body);
  if (!needsBlocks)
    return true;
  Operation *parent = call->getParentOp();
  return parent->getName() == callee->getName() || !parent->mightHaveTrait<OpTrait::SingleBlock>();
}

idr::inlining::Step
idr::inlining::inlineCalls(FuncOp caller,
                           llvm::function_ref<const optimize::Node *(StringAttr)> nodeOf) {
  Step step;
  SmallVector<CallOp> calls;
  caller.getBody().walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
  if (calls.empty())
    return step;
  int64_t size = inlineSize(caller);
  InlinerInterface interface(caller.getContext());
  InlinerConfig config;
  for (CallOp call : calls) {
    const optimize::Node *callee = nodeOf(call.getCalleeAttr().getAttr());
    // A callee that is not final is a member of the caller's own
    // component: never inlined, and never read.
    if (!callee || !callee->isFinal())
      continue;
    FuncOp fn = callee->fn;
    const Facts &facts = callee->summary.facts;
    if (!worthInlining(facts, fn.getNoInline()) || !fitsRegion(interface, call, fn))
      continue;
    if (!fitsCap(size, facts.size)) {
      ++step.capped;
      continue;
    }
    if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                          /*shouldCloneInlinedRegion=*/true)))
      continue;
    caller.absorb(fn);
    call.erase();
    size += facts.size - 1;
    ++step.inlined;
  }
  return step;
}
