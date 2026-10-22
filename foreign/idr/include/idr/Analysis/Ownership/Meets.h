// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a value graded with a stronger sharing claim meets a position that
// takes a weaker one (a call's parameter, a function's result, a region's
// input, an operand of an op of upstream's, which takes the bare carrier),
// it is shared into it by idr.count.share, the one way a claim goes down.
// The passes that write a claim into the types (idr-in-place, the commit of
// idr-rc-exclusive) write it where it is proved, then meet every position
// once; a position that asks more than its value has is the writer's bug,
// which the verifier after the pass reports.
#ifndef IDR_ANALYSIS_OWNERSHIP_MEETS_H
#define IDR_ANALYSIS_OWNERSHIP_MEETS_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <utility>

namespace idr::ownership {

// `use` shared into `slot`, when its value claims more of its sharing than
// the slot takes.
inline void shareInto(mlir::RewriterBase &rewriter, mlir::OpOperand &use, mlir::Type slot) {
  mlir::Type type = use.get().getType();
  std::optional<Hold> held = holdOf(type);
  std::optional<Hold> taken = holdOf(slot);
  if (type == slot || !held || !taken || taken->claims(held->claim()))
    return;
  mlir::Operation *owner = use.getOwner();
  rewriter.setInsertionPoint(owner);
  mlir::Value shared = CountShareOp::create(rewriter, owner->getLoc(), slot, use.get());
  rewriter.modifyOpInPlace(owner, [&] { use.set(shared); });
}

// Every position of `fn` met: each call's arguments with its callee's
// parameters (`calleeOf` names the callee), the return's operands with the
// function's results, and each value a region branch or a jump forwards
// with the input it becomes. Found first and met after, as a meeting adds a
// use.
template <typename CalleeOf>
  requires std::is_invocable_r_v<FuncOp, CalleeOf &, CallOp>
void shareIntoPositions(FuncOp fn, CalleeOf &&calleeOf) {
  llvm::SmallVector<std::pair<mlir::OpOperand *, mlir::Type>> positions;
  fn.walk([&](mlir::Operation *op) {
    if (auto call = llvm::dyn_cast<CallOp>(op)) {
      FuncOp callee = calleeOf(call);
      for (auto [use, type] : llvm::zip(call.getArgOperandsMutable(), callee.getArgumentTypes()))
        positions.emplace_back(&use, type);
    } else if (auto ret = llvm::dyn_cast<ReturnOp>(op)) {
      for (auto [use, type] : llvm::zip(ret->getOpOperands(), fn.getResultTypes()))
        positions.emplace_back(&use, type);
    }
    forwardedValues(op, [&](mlir::OpOperand &operand, mlir::Value input) {
      positions.emplace_back(&operand, input.getType());
    });
  });
  mlir::IRRewriter rewriter(fn.getContext());
  for (auto [use, slot] : positions)
    shareInto(rewriter, *use, slot);
}

// Every operand of an op of upstream's in `fn`, met at its bare grade: such
// an op takes only the bare carrier, so a value a pass raised reaches it
// shared. Only a pass before placement meets them, since a share consumes
// its operand and such an op only reads it; exclusivity, after placement,
// follows no value such an op reads.
inline void shareIntoCarriers(FuncOp fn) {
  llvm::SmallVector<mlir::OpOperand *> reads;
  fn.walk([&](mlir::Operation *op) {
    if (readsOnlyCarriers(op))
      for (mlir::OpOperand &use : op->getOpOperands())
        reads.push_back(&use);
  });
  mlir::IRRewriter rewriter(fn.getContext());
  for (mlir::OpOperand *use : reads)
    shareInto(rewriter, *use, idr::shared(use->get().getType()));
}

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_MEETS_H
