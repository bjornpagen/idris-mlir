// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When a call may be raised, and the key of its raised clone.
//
// Raising moves the callee's body from the call to its consumer, so nothing
// may run between them that could tell: the consumer and the projection are
// in the call's block, and either the call only computes (it performs no IO,
// cannot crash and returns; building actions is no IO), or every op between
// it and the consumer only computes. A call that passes a world is never
// raised: the callee's body would take part in the world chain.
//
// Both are read from the call alone, its operands, its own effects and the
// ops around it, so a function pass asks them without resolving the callee.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/IR/Symbols.h"
#include "idr/Analysis/Holds.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

std::optional<Consumer> consumerOf(idr::CallOp call, const Holds &holds) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  // The operands have the callee's parameter types, so a world one of them
  // may hold is one the callee takes.
  if (llvm::any_of(call.getArgs().getTypes(), [&](Type type) { return holds.mayHoldWorld(type); }))
    return std::nullopt;
  std::optional<Elimination> e = eliminationAt(*call->getResult(0).getUses().begin());
  if (!e || e->apply->getBlock() != call->getBlock())
    return std::nullopt;
  ApplyOp apply = e->apply;
  // A call that only computes may run later, after anything between it and
  // its consumer; any other only after ops that only compute. A call's
  // effects hold its callee's, and every one of them is more than
  // computing, whatever closures the arguments hold. A call without effects
  // may do anything, and the ops between are walked.
  if (!idr::onlyAllocates(call))
    for (Operation *op = call->getNextNode(); op != apply; op = op->getNextNode())
      if (!idr::onlyAllocates(op))
        return std::nullopt;
  return e;
}

// The callee and its consumer: a call of the callee in the clone whose
// result is consumed the same way, which inlining exposes where an action
// recurs, becomes a self call. The callee's arity is the call's operand
// count. Whether a linear value is used on the way follows from the types,
// so the key need not say.
Attribute raiseKey(idr::CallOp call, Consumer consumer) {
  MLIRContext *ctx = call.getContext();
  StringAttr name = call.getCalleeAttr().getAttr();
  auto arity = static_cast<unsigned>(call.getArgs().size());
  if (!consumer.field)
    return KeyApplyAttr::get(ctx, name, arity);
  return KeyApplyFieldAttr::get(ctx, name, arity, consumer.field.getCtorAttr().getAttr(),
                                static_cast<unsigned>(consumer.field.getIndex()));
}

} // namespace idr::specialize
