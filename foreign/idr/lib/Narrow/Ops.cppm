// idr.narrow:ops: an op whose bigs all fit made an op on words.
module;
// llvm_unreachable is a macro, which no import carries.
#include "llvm/Support/ErrorHandling.h"

export module idr.narrow:ops;

import idr.mlir;
import idr.dialect;

import :facts;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

arith::IntegerOverflowFlags noWrap(bool nonNegative) {
  return nonNegative ? arith::IntegerOverflowFlags::nsw | arith::IntegerOverflowFlags::nuw
                     : arith::IntegerOverflowFlags::nsw;
}

arith::CmpIPredicate signedPredicate(CmpPredicate predicate) {
  switch (predicate) {
  case CmpPredicate::eq:
    return arith::CmpIPredicate::eq;
  case CmpPredicate::lt:
    return arith::CmpIPredicate::slt;
  case CmpPredicate::lte:
    return arith::CmpIPredicate::sle;
  case CmpPredicate::gt:
    return arith::CmpIPredicate::sgt;
  case CmpPredicate::gte:
    return arith::CmpIPredicate::sge;
  }
  llvm_unreachable("a comparison predicate");
}

// Replaces `op`'s big result by the big of `word`.
void replaceBig(RewriterBase &rewriter, Facts &facts, Operation *op, Value word) {
  Value result = op->getResult(0);
  Value big = facts.big(rewriter, op->getLoc(), result.getType(), word, facts.of(result));
  rewriter.replaceOp(op, big);
}

// A match on a big that fits is a match on its word, when every key is a
// word too.
bool narrowMatch(RewriterBase &rewriter, Facts &facts, MatchLitOp match) {
  Value scrutinee = match.getScrutinee();
  if (!facts.fits(scrutinee))
    return false;
  SmallVector<Attribute> keys;
  for (Attribute key : match.getCases()) {
    int64_t value = 0;
    if (cast<BigAttr>(key).getValue().getAsInteger(10, value))
      return false;
    keys.push_back(rewriter.getI64IntegerAttr(value));
  }
  rewriter.setInsertionPoint(match);
  Value word = facts.word(rewriter, match.getLoc(), scrutinee);
  rewriter.modifyOpInPlace(match, [&] {
    match->setOperand(0, word);
    match.setCasesAttr(rewriter.getArrayAttr(keys));
  });
  return true;
}

// Rewrites one op whose bigs all fit; false when they do not all fit.
bool narrowOp(RewriterBase &rewriter, Facts &facts, Operation *op) {
  if (auto match = dyn_cast<MatchLitOp>(op))
    return narrowMatch(rewriter, facts, match);
  auto allFit = [&](ValueRange values) {
    return llvm::all_of(values, [&](Value v) { return !isBig(v.getType()) || facts.fits(v); });
  };
  if (!allFit(op->getOperands()) || !allFit(op->getResults()))
    return false;
  rewriter.setInsertionPoint(op);
  Location loc = op->getLoc();
  auto word = [&](Value v) { return facts.word(rewriter, loc, v); };
  bool nonNegative = facts.nonNegative(op->getOperands()) && facts.nonNegative(op->getResults());
  return llvm::TypeSwitch<Operation *, bool>(op)
      .Case([&](BigAddOp add) {
        replaceBig(rewriter, facts, op,
                   arith::AddIOp::create(rewriter, loc, word(add.getLhs()), word(add.getRhs()),
                                         noWrap(nonNegative)));
        return true;
      })
      .Case([&](BigSubOp sub) {
        replaceBig(rewriter, facts, op,
                   arith::SubIOp::create(rewriter, loc, word(sub.getLhs()), word(sub.getRhs()),
                                         noWrap(nonNegative)));
        return true;
      })
      .Case([&](BigMulOp mul) {
        replaceBig(rewriter, facts, op,
                   arith::MulIOp::create(rewriter, loc, word(mul.getLhs()), word(mul.getRhs()),
                                         noWrap(nonNegative)));
        return true;
      })
      // The operand is at least 1.
      .Case([&](BigPredOp pred) {
        Value one = arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(1));
        replaceBig(rewriter, facts, op,
                   arith::SubIOp::create(rewriter, loc, word(pred.getValue()), one, noWrap(true)));
        return true;
      })
      .Case([&](BigCmpOp cmp) {
        rewriter.replaceOpWithNewOp<arith::CmpIOp>(op, signedPredicate(cmp.getPredicate()),
                                                   word(cmp.getLhs()), word(cmp.getRhs()));
        return true;
      })
      .Case([&](NatFromBigOp clamp) {
        Value value = word(clamp.getValue());
        if (!facts.nonNegative(clamp.getValue()))
          value = arith::MaxSIOp::create(
              rewriter, loc, value, arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(0)));
        replaceBig(rewriter, facts, op, value);
        return true;
      })
      // The Integer a natural is takes the natural's reference; the word
      // takes none, so the natural drops it.
      .Case([&](NatToBigOp retype) {
        Value natural = retype.getValue();
        Value value = word(natural);
        if (facts.owned(natural))
          DropOp::create(rewriter, loc, natural);
        replaceBig(rewriter, facts, op, value);
        return true;
      })
      .Case([&](BigToIntOp toInt) {
        Value value = word(toInt.getValue());
        if (value.getType() != toInt.getType())
          value = arith::TruncIOp::create(rewriter, loc, toInt.getType(), value);
        rewriter.replaceOp(op, value);
        return true;
      })
      // A big the pass made of a word holds no count. Any other big
      // proved small keeps its count ops: counting still tracks it (a call's
      // result, a parameter), and on a small they do nothing at runtime.
      .Case<DupOp, DropOp>([&](Operation *) {
        Value value = op->getOperand(0);
        if (!isBig(value.getType()) || !value.getDefiningOp<BigSmallOp>())
          return false;
        rewriter.eraseOp(op);
        return true;
      })
      .Default([](Operation *) { return false; });
}

} // namespace idr::narrow
