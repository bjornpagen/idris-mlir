// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op whose bigs all fit made an op on words.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

// The word op of each big op that names one: BigToWord.
#include "idr/IR/Generated/BigToWord.h.inc"

#include <type_traits>

using namespace mlir;

namespace idr::narrow {

namespace {

// idr-narrow attempts to make one op on bigs an op on words, as upstream's
// apply-pattern attempts a pattern; the unit is the op.
struct NarrowWordAction : support::TaggedAction<NarrowWordAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::narrowWord;
};

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
// word too. Its default region binds the scrutinee, so it binds the word
// now, and what read the big there reads the big of the word, a small big
// that owns nothing, with the scrutinee's bounds.
bool narrowMatch(RewriterBase &rewriter, Facts &facts, LitMatchOp match) {
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
  ranges::Bounds bounds = facts.of(scrutinee);
  rewriter.setInsertionPoint(match);
  Value word = facts.word(rewriter, match.getLoc(), scrutinee);
  BlockArgument rebound = match.getDefaultRegion().getArgument(0);
  Type big = rebound.getType();
  rewriter.modifyOpInPlace(match, [&] {
    match->setOperand(0, word);
    match.setCasesAttr(rewriter.getArrayAttr(keys));
    rebound.setType(word.getType());
  });
  rewriter.setInsertionPointToStart(rebound.getOwner());
  Value same = facts.big(rewriter, rebound.getLoc(), big, rebound, bounds);
  rewriter.replaceAllUsesExcept(rebound, same, same.getDefiningOp());
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
    if (effects::consumes(operand) && facts.owned(operand.get()))
      CountDropOp::create(rewriter, loc, operand.get());
  if (isBig(big->getResult(0).getType()))
    replaceBig(rewriter, facts, big, word);
  else
    rewriter.replaceOp(big, word);
  return true;
}

// Whether every big `op` takes and gives fits.
bool allFit(const Facts &facts, Operation *op) {
  auto fit = [&](Value v) { return !isBig(v.getType()) || facts.fits(v); };
  return llvm::all_of(op->getOperands(), fit) && llvm::all_of(op->getResults(), fit);
}

// Rewrites one op whose bigs all fit; false, having changed nothing, when
// they do not all fit or the op has no word form. The one dispatch on the
// ops that have one.
bool narrowOp(RewriterBase &rewriter, Facts &facts, Operation *op) {
  rewriter.setInsertionPoint(op);
  Location loc = op->getLoc();
  return llvm::TypeSwitch<Operation *, bool>(op)
      .Case([&](LitMatchOp match) { return narrowMatch(rewriter, facts, match); })
      .Case<
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/Generated/BigToWord.h.inc"
          >([&](auto big) {
            if (!allFit(facts, op))
              return false;
            bool nonNegative =
                facts.nonNegative(op->getOperands()) && facts.nonNegative(op->getResults());
            return narrowBig(rewriter, facts, big, nonNegative);
          })
      // A guard's result is its operand, so the guard of a big divisor that
      // fits guards its word, and the divisor is the big of the checked
      // word. The guard took the big's reference; the word takes none, so
      // the big drops it.
      .Case([&](CheckNonzeroOp check) {
        Value divisor = check.getValue();
        if (!isBig(divisor.getType()) || !allFit(facts, op))
          return false;
        Value value = facts.word(rewriter, loc, divisor);
        Value checked = CheckNonzeroOp::create(rewriter, loc, value.getType(), value,
                                               check.getCause(), check.getSiteAttr());
        if (facts.owned(divisor))
          CountDropOp::create(rewriter, loc, divisor);
        replaceBig(rewriter, facts, op, checked);
        return true;
      })
      // A big the pass made of a word holds no count. Any other big
      // proved small keeps its count ops: counting still tracks it (a call's
      // result, a parameter), and on a small they do nothing at runtime.
      .Case<CountDupOp, CountDropOp>([&](Operation *) {
        Value value = op->getOperand(0);
        if (!isBig(value.getType()) || !value.getDefiningOp<BigSmallOp>() || !allFit(facts, op))
          return false;
        rewriter.eraseOp(op);
        return true;
      })
      // Any other op has no word form.
      .Default([](Operation *) { return false; });
}

// An op on bigs that all fit, reached after the joints made words of what
// flows round loops and out of merges. A conversion the joints made is
// left to the folds that pair it, not narrowed again. Rooted at each op
// narrowOp has a case for, from the same generated list its dispatch
// reads, so the driver attempts it only where it can narrow.
struct NarrowWord : RewritePattern {
  NarrowWord(StringRef root, MLIRContext *ctx, Facts &facts, uint64_t &narrowed)
      : RewritePattern(root, /*benefit=*/1, ctx), facts(facts), narrowed(narrowed) {}

  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rewriter) const override {
    if (facts.made(op) || (llvm::none_of(op->getOperandTypes(), isBig) &&
                           llvm::none_of(op->getResultTypes(), isBig)))
      return failure();
    bool done = false;
    (void)support::perform<NarrowWordAction>(op, [&] { done = narrowOp(rewriter, facts, op); });
    if (!done)
      return failure();
    ++narrowed;
    return success();
  }

  Facts &facts;
  uint64_t &narrowed;
};

} // namespace

// One NarrowWord rooted at each op of `OpTs`.
template <typename... OpTs>
void addNarrowWords(RewritePatternSet &patterns, Facts &facts, uint64_t &narrowed) {
  (patterns.add<NarrowWord>(OpTs::getOperationName(), patterns.getContext(), facts, narrowed),
   ...);
}

void populateWordPatterns(RewritePatternSet &patterns, Facts &facts, uint64_t &narrowed) {
  // narrowOp's cases: the big ops with a word form, which the ODS names,
  // the literal match and the guard on a big, and counting a big made of
  // a word.
  addNarrowWords<LitMatchOp, CheckNonzeroOp, CountDupOp, CountDropOp,
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/Generated/BigToWord.h.inc"
                 >(patterns, facts, narrowed);
}

} // namespace idr::narrow
