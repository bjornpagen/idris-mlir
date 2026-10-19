// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-commit: what exclusivity's solve proved, written into one
// function's types once idr-rc-exclusive has written it into every
// signature: the
// values it proved exclusive get the grade, and where an exclusive value
// meets a position typed owned (a call's argument, a return, and whatever
// a branch or a region branch forwards it to: a loop's carried value, its
// result, a match's result), it is shared into it.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/MapVector.h"

using namespace mlir;

namespace idr::ownership {

namespace {

// `operand` where `expected` is taken: an exclusive value is shared into
// an owned position. An owned one in an exclusive position is on a path
// the solver never reached (whose values it never graded): that path
// never runs, so it ends there (`dead`), and no reference stands on it;
// anywhere else it is the solver and the commit disagreeing, which is a
// bug here, never a program to compile.
LogicalResult meet(RewriterBase &rewriter, const Exclusivity &solved, OpOperand &operand,
                   Type expected, llvm::MapVector<Block *, Operation *> &dead) {
  Type type = operand.get().getType();
  if (type == expected || !isOwned(expected))
    return success();
  Operation *op = operand.getOwner();
  if (isExclusive(type) && !isExclusive(expected)) {
    rewriter.setInsertionPoint(op);
    Value shared = ShareOp::create(rewriter, op->getLoc(), expected, operand.get());
    rewriter.modifyOpInPlace(op, [&] { operand.set(shared); });
    return success();
  }
  if (!isExclusive(type) && isExclusive(expected)) {
    if (solved.live(op->getBlock()))
      return op->emitOpError("idr-rc-exclusive: gives a value of ")
             << type << " where the solver proved " << expected;
    auto [at, fresh] = dead.try_emplace(op->getBlock(), op);
    if (!fresh && op->isBeforeInBlock(at->second))
      at->second = op;
  }
  return success();
}

// A path the solver never reached ends at `op`, its first op that takes a
// value the solver did not grade: ub.unreachable there, and what came after
// it erased, the block's terminator with it.
void endPath(RewriterBase &rewriter, Operation *op) {
  Block *block = op->getBlock();
  while (&block->back() != op) {
    Operation *last = &block->back();
    last->dropAllUses();
    rewriter.eraseOp(last);
  }
  op->dropAllUses();
  rewriter.setInsertionPoint(op);
  ub::UnreachableOp::create(rewriter, op->getLoc());
  rewriter.eraseOp(op);
}

// The commit of `fn`; the values it leaves exclusive are counted into
// `exclusives`.
LogicalResult commit(FuncOp fn, const Exclusivity &solved, const SymbolTable &symbols,
                     unsigned &exclusives) {
  // A call's results are its callee's, which idr-rc-exclusive set from the
  // signature already: on a path the solver never reached, a call has no
  // lattice of its own.
  fn.walk<WalkOrder::PreOrder>([&](Block *block) {
    for (BlockArgument arg : block->getArguments()) {
      if (solved.proves(arg))
        arg.setType(exclusive(arg.getType()));
      exclusives += isExclusive(arg.getType());
    }
    for (Operation &op : *block)
      for (Value result : op.getResults()) {
        if (!isa<CallOp>(op) && solved.proves(result))
          result.setType(exclusive(result.getType()));
        exclusives += isExclusive(result.getType());
      }
  });
  // Every position now says what it takes: found first, then met, since a
  // meeting inserts an op before the one that takes the value.
  SmallVector<std::pair<OpOperand *, Type>> positions;
  auto take = [&](auto &&operands, TypeRange expected) {
    for (auto [operand, type] : llvm::zip(operands, expected))
      positions.emplace_back(&operand, type);
  };
  fn.walk([&](Operation *op) {
    // A verified call names a function of the program.
    if (auto call = dyn_cast<CallOp>(op)) {
      take(call.getArgOperandsMutable(),
           symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr()).getArgumentTypes());
    } else if (auto ret = dyn_cast<ReturnOp>(op)) {
      take(ret->getOpOperands(), fn.getResultTypes());
    }
    forwardedValues(op, [&](OpOperand &operand, Value input) {
      positions.emplace_back(&operand, input.getType());
    });
  });
  IRRewriter rewriter(fn.getContext());
  // The paths never reached, each ended once every position is met: the
  // walk found the positions inside an op before the op's own, so an
  // inner path ends before the one that erases it.
  llvm::MapVector<Block *, Operation *> dead;
  for (auto [operand, expected] : positions)
    if (failed(meet(rewriter, solved, *operand, expected, dead)))
      return failure();
  for (auto [block, op] : dead)
    endPath(rewriter, op);
  // A share that gives its value at the value's own type, neither
  // exclusive nor raised to the frame, shares nothing.
  SmallVector<ShareOp> idle;
  fn.walk([&](ShareOp share) {
    if (share.getValue().getType() == share.getType())
      idle.push_back(share);
  });
  for (ShareOp share : idle)
    rewriter.replaceOp(share, share.getValue());
  return success();
}

// The solve and the table idr-rc-exclusive holds for the nested run, which
// reads them from every thread and writes nothing of them, and the
// statistic it counts into, which takes a count from every thread.
struct RcCommit : PassWrapper<RcCommit, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RcCommit)

  RcCommit(const Exclusivity &solved, const SymbolTable &symbols, Pass::Statistic &exclusive)
      : solved(solved), symbols(symbols), exclusive(exclusive) {}

  StringRef getArgument() const override { return "idr-rc-commit"; }
  StringRef getDescription() const override {
    return "Write the exclusive grades idr-rc-exclusive proved into one function and share an exclusive "
           "value into each owned position";
  }

  void runOnOperation() override {
    unsigned exclusives = 0;
    if (failed(commit(getOperation(), solved, symbols, exclusives)))
      return signalPassFailure();
    exclusive += exclusives;
  }

  const Exclusivity &solved;
  const SymbolTable &symbols;
  Pass::Statistic &exclusive;
};

} // namespace

std::unique_ptr<Pass> createRcCommit(const Exclusivity &solved, const SymbolTable &symbols,
                                     Pass::Statistic &exclusive) {
  return std::make_unique<RcCommit>(solved, symbols, exclusive);
}

} // namespace idr::ownership
