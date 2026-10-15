// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op whose bigs all fit made an op on words.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

// The word op of each big op that names one: BigToWord.
#include "idr/IR/IdrBigToWord.inc"

#include <type_traits>

using namespace mlir;

namespace idr::narrow {

namespace {

arith::IntegerOverflowFlags noWrap(bool nonNegative) {
  return nonNegative ? arith::IntegerOverflowFlags::nsw | arith::IntegerOverflowFlags::nuw
                     : arith::IntegerOverflowFlags::nsw;
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
    const APInt &value = cast<BigAttr>(key).getValue();
    if (value.getSignificantBits() > 64)
      return false;
    keys.push_back(rewriter.getI64IntegerAttr(value.getSExtValue()));
  }
  rewriter.setInsertionPoint(match);
  Value word = facts.word(rewriter, match.getLoc(), scrutinee);
  rewriter.modifyOpInPlace(match, [&] {
    match->setOperand(0, word);
    match.setCasesAttr(rewriter.getArrayAttr(keys));
  });
  return true;
}

// The word of what the big op `big` computes, on the words of its
// operands: the word op it names (BigToWord) applied to them and, where it
// names one, to its constant after them; the word itself where it names no
// op. A sum, difference or product carries no wrap, and none unsigned when
// nothing is negative; a comparison is its predicate on words, signed; a
// conversion to an integer narrower than the word truncates; the larger of
// a value that is not negative and 0 is the value.
template <typename OpT>
Value wordOf(RewriterBase &rewriter, Facts &facts, OpT big, bool nonNegative) {
  using Word = typename BigToWord<OpT>::Op;
  Location loc = big.getLoc();
  SmallVector<Value> words;
  for (Value operand : big->getOperands())
    words.push_back(facts.word(rewriter, loc, operand));
  auto constant = [&](int64_t value) {
    return arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(value));
  };
  if constexpr (std::is_void_v<Word>) {
    return words.front();
  } else if constexpr (std::is_same_v<Word, arith::CmpIOp>) {
    return arith::CmpIOp::create(rewriter, loc, layout::signedPredicate(big.getPredicate()),
                                 words[0], words[1]);
  } else if constexpr (std::is_same_v<Word, arith::TruncIOp>) {
    Type type = big.getType();
    return type == words.front().getType()
               ? words.front()
               : Value(arith::TruncIOp::create(rewriter, loc, type, words.front()));
  } else if constexpr (std::is_same_v<Word, arith::MaxSIOp>) {
    return nonNegative ? words.front()
                       : Value(arith::MaxSIOp::create(rewriter, loc, words.front(),
                                                      constant(BigToWord<OpT>::constant)));
  } else {
    Value rhs;
    if constexpr (requires { BigToWord<OpT>::constant; })
      rhs = constant(BigToWord<OpT>::constant);
    else
      rhs = words[1];
    return Word::create(rewriter, loc, words.front(), rhs, noWrap(nonNegative));
  }
}

// A big op whose bigs all fit made its word op. What it took over the
// word takes nothing of, so the big it took drops its reference there.
template <typename OpT>
bool narrowBig(RewriterBase &rewriter, Facts &facts, OpT big, bool nonNegative) {
  Location loc = big.getLoc();
  Value word = wordOf(rewriter, facts, big, nonNegative);
  for (OpOperand &operand : big->getOpOperands())
    if (consumes(operand) && facts.owned(operand.get()))
      DropOp::create(rewriter, loc, operand.get());
  if (isBig(big->getResult(0).getType()))
    replaceBig(rewriter, facts, big, word);
  else
    rewriter.replaceOp(big, word);
  return true;
}

// Rewrites one op whose bigs all fit; false, having changed nothing, when
// they do not all fit.
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
  bool nonNegative = facts.nonNegative(op->getOperands()) && facts.nonNegative(op->getResults());
  return llvm::TypeSwitch<Operation *, bool>(op)
      .Case<
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/IdrBigToWord.inc"
          >([&](auto big) { return narrowBig(rewriter, facts, big, nonNegative); })
      // A guard's result is its operand, so the guard of a big divisor that
      // fits guards its word, and the divisor is the big of the checked
      // word. The guard took the big's reference; the word takes none, so
      // the big drops it.
      .Case([&](CheckNonzeroOp check) {
        Value divisor = check.getValue();
        if (!isBig(divisor.getType()))
          return false;
        Value value = facts.word(rewriter, loc, divisor);
        Value checked = CheckNonzeroOp::create(rewriter, loc, value.getType(), value,
                                               check.getCauseAttr());
        if (facts.owned(divisor))
          DropOp::create(rewriter, loc, divisor);
        replaceBig(rewriter, facts, op, checked);
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

// An op on bigs that all fit, reached after the joints made words of what
// flows round loops and out of merges. A conversion the joints made is
// left to the folds that pair it, not narrowed again.
struct NarrowWord : RewritePattern {
  NarrowWord(MLIRContext *ctx, Facts &facts, uint64_t &narrowed)
      : RewritePattern(MatchAnyOpTypeTag(), /*benefit=*/1, ctx), facts(facts), narrowed(narrowed) {}

  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rewriter) const override {
    if (!isa<MatchLitOp, CheckNonzeroOp, DupOp, DropOp,
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/IdrBigToWord.inc"
             >(op) ||
        facts.made(op) || !narrowOp(rewriter, facts, op))
      return failure();
    ++narrowed;
    return success();
  }

  Facts &facts;
  uint64_t &narrowed;
};

} // namespace

void populateWordPatterns(RewritePatternSet &patterns, Facts &facts, uint64_t &narrowed) {
  patterns.add<NarrowWord>(patterns.getContext(), facts, narrowed);
}

} // namespace idr::narrow
