// idr.narrow:carried: the values that flow around loops and out of merges
// made words where every value that may flow there fits.
export module idr.narrow:carried;

import idr.mlir;
import idr.dialect;
import idr.ranges;

import :facts;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

using ranges::Bounds;

// Retypes the big block argument `arg` to i64: its uses get the big of it.
void narrowArgument(RewriterBase &rewriter, Facts &facts, BlockArgument arg) {
  Bounds bounds = facts.of(arg);
  Type type = arg.getType();
  arg.setType(rewriter.getI64Type());
  rewriter.setInsertionPointToStart(arg.getOwner());
  Value big = facts.big(rewriter, arg.getLoc(), type, arg, bounds);
  rewriter.replaceAllUsesExcept(arg, big, big.getDefiningOp());
}

// Retypes the big result `result` to i64: its uses get the big of it.
void narrowResult(RewriterBase &rewriter, Facts &facts, OpResult result) {
  Bounds bounds = facts.of(result);
  Type type = result.getType();
  result.setType(rewriter.getI64Type());
  rewriter.setInsertionPointAfter(result.getOwner());
  Value big = facts.big(rewriter, result.getLoc(), type, result, bounds);
  rewriter.replaceAllUsesExcept(result, big, big.getDefiningOp());
}

// Passes the word of operand `index` of `op` instead of the big. The
// operands narrowed here are consumed where they are passed (a loop's
// start, a yield), so a big that held a reference drops it there: counting
// ran before, and the word takes nothing.
void passWord(RewriterBase &rewriter, Facts &facts, Operation *op, unsigned index) {
  rewriter.setInsertionPoint(op);
  Value big = op->getOperand(index);
  Value word = facts.word(rewriter, op->getLoc(), big);
  rewriter.modifyOpInPlace(op, [&] { op->setOperand(index, word); });
  if (facts.owned(big))
    DropOp::create(rewriter, op->getLoc(), big);
}

// The values that flow around loops and out of merges, where every value
// that may flow there fits: the webs' joints.
unsigned narrowCarried(RewriterBase &rewriter, Facts &facts, Operation *op) {
  unsigned count = 0;
  if (auto loop = dyn_cast<scf::WhileOp>(op)) {
    Block &before = loop.getBefore().front();
    Block &after = loop.getAfter().front();
    auto yield = cast<scf::YieldOp>(after.getTerminator());
    auto condition = loop.getConditionOp();
    for (BlockArgument arg : before.getArguments()) {
      unsigned i = arg.getArgNumber();
      if (!facts.fits(arg) || !facts.fits(loop.getInits()[i]) || !facts.fits(yield.getOperand(i)))
        continue;
      passWord(rewriter, facts, loop, i);
      passWord(rewriter, facts, yield, i);
      narrowArgument(rewriter, facts, arg);
      ++count;
    }
    for (BlockArgument arg : after.getArguments()) {
      unsigned j = arg.getArgNumber();
      OpResult result = loop->getResult(j);
      if (!facts.fits(arg) || !facts.fits(result) || !facts.fits(condition.getArgs()[j]))
        continue;
      passWord(rewriter, facts, condition, j + 1);
      narrowArgument(rewriter, facts, arg);
      narrowResult(rewriter, facts, result);
      ++count;
    }
    return count;
  }
  if (auto loop = dyn_cast<scf::ForOp>(op)) {
    auto yield = cast<scf::YieldOp>(loop.getBody()->getTerminator());
    for (auto [i, arg] : llvm::enumerate(loop.getRegionIterArgs())) {
      OpResult result = loop->getResult(static_cast<unsigned>(i));
      if (!facts.fits(arg) || !facts.fits(result) || !facts.fits(loop.getInitArgs()[i]) ||
          !facts.fits(yield.getOperand(static_cast<unsigned>(i))))
        continue;
      passWord(rewriter, facts, loop, loop.getNumControlOperands() + static_cast<unsigned>(i));
      passWord(rewriter, facts, yield, static_cast<unsigned>(i));
      narrowArgument(rewriter, facts, arg);
      narrowResult(rewriter, facts, result);
      ++count;
    }
    return count;
  }
  // A merge: every region's yield gives the result, but for a region that
  // ends the program, which yields nothing.
  if (isa<scf::IfOp, scf::IndexSwitchOp, MatchOp, MatchLitOp>(op)) {
    SmallVector<Operation *> yields;
    for (Region &region : op->getRegions())
      if (!region.empty() && region.front().getTerminator()->getNumOperands() == op->getNumResults())
        yields.push_back(region.front().getTerminator());
    for (OpResult result : op->getResults()) {
      unsigned k = result.getResultNumber();
      if (!facts.fits(result) ||
          !llvm::all_of(yields, [&](Operation *y) { return facts.fits(y->getOperand(k)); }))
        continue;
      for (Operation *y : yields)
        passWord(rewriter, facts, y, k);
      narrowResult(rewriter, facts, result);
      ++count;
    }
  }
  return count;
}

} // namespace idr::narrow
