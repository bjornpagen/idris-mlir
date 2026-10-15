// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-commit: what exclusivity's solve proved, written into one
// function's types once idr-rc has written it into every signature: the
// values it proved exclusive get the grade, and where an exclusive value
// meets a position typed owned (a call's argument, a return, and whatever
// a branch or a region branch forwards it to: a loop's carried value, its
// result, a match's result), it is shared into it.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace idr::ownership {

namespace {

// `operand` where `expected` is taken: an exclusive value is shared into
// an owned position. An owned one in an exclusive position is on a path
// the solver never reached (whose values it never graded), where it is
// poison; anywhere else it is the solver and the commit disagreeing,
// which is a bug here, never a program to compile.
LogicalResult meet(RewriterBase &rewriter, const Exclusivity &solved, OpOperand &operand,
                   Type expected) {
  Type type = operand.get().getType();
  if (type == expected || !isOwned(expected))
    return success();
  Operation *op = operand.getOwner();
  rewriter.setInsertionPoint(op);
  if (isExclusive(type) && !isExclusive(expected)) {
    Value shared = ShareOp::create(rewriter, op->getLoc(), expected, operand.get());
    rewriter.modifyOpInPlace(op, [&] { operand.set(shared); });
    return success();
  }
  if (!isExclusive(type) && isExclusive(expected)) {
    if (solved.live(op->getBlock()))
      return op->emitOpError("idr-rc: gives a value of ")
             << type << " where the solver proved " << expected;
    Value poison = ub::PoisonOp::create(rewriter, op->getLoc(), expected);
    rewriter.modifyOpInPlace(op, [&] { operand.set(poison); });
  }
  return success();
}

LogicalResult commit(FuncOp fn, const Exclusivity &solved, SymbolTable &symbols) {
  // A call's results are its callee's, which idr-rc set from the signature
  // already: on a path the solver never reached, a call has no lattice of
  // its own.
  fn.walk<WalkOrder::PreOrder>([&](Block *block) {
    for (BlockArgument arg : block->getArguments())
      if (solved.proves(arg))
        arg.setType(exclusive(arg.getType()));
    for (Operation &op : *block)
      if (!isa<CallOp>(op))
        for (Value result : op.getResults())
          if (solved.proves(result))
            result.setType(exclusive(result.getType()));
  });
  // Every position now says what it takes: found first, then met, since a
  // meeting inserts an op before the one that takes the value.
  SmallVector<std::pair<OpOperand *, Type>> positions;
  auto take = [&](auto &&operands, TypeRange expected) {
    for (auto [operand, type] : llvm::zip(operands, expected))
      positions.emplace_back(&operand, type);
  };
  fn.walk([&](Operation *op) {
    if (auto call = dyn_cast<CallOp>(op)) {
      if (auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr()))
        take(call.getArgOperandsMutable(), callee.getArgumentTypes());
    } else if (auto ret = dyn_cast<ReturnOp>(op)) {
      take(ret->getOpOperands(), fn.getResultTypes());
    }
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      positions.emplace_back(&operand, input.getType());
    });
  });
  IRRewriter rewriter(fn.getContext());
  for (auto [operand, expected] : positions)
    if (failed(meet(rewriter, solved, *operand, expected)))
      return failure();
  // A share of a value that is not exclusive shares nothing.
  SmallVector<ShareOp> idle;
  fn.walk([&](ShareOp share) {
    if (!isExclusive(share.getValue().getType()))
      idle.push_back(share);
  });
  for (ShareOp share : idle)
    rewriter.replaceOp(share, share.getValue());
  return success();
}

struct RcCommit : PassWrapper<RcCommit, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RcCommit)

  StringRef getArgument() const override { return "idr-rc-commit"; }
  StringRef getDescription() const override {
    return "Write the exclusive grades idr-rc proved into one function and share an exclusive "
           "value into each owned position";
  }

  void runOnOperation() override {
    FuncOp fn = getOperation();
    auto solved = getCachedParentAnalysis<Exclusivity>();
    auto symbols = getCachedParentAnalysis<SymbolTable>();
    if (!solved || !symbols) {
      fn.emitError("idr-rc-commit: internal error: the module's Exclusivity or SymbolTable was "
                   "not computed");
      return signalPassFailure();
    }
    if (failed(commit(fn, solved->get(), symbols->get())))
      signalPassFailure();
  }
};

} // namespace

std::unique_ptr<Pass> createRcCommit() { return std::make_unique<RcCommit>(); }

} // namespace idr::ownership
