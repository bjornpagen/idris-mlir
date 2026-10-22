// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op whose bigs all fit made an op on words. Each pattern is rooted at
// its op, so MLIR finds the one for the op the rewrite is at; it decides on
// the numbers of what the op took and gave as the walk met it, which the
// bigs standing in for them share, and then rewrites.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"

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

// Whether a narrowed op takes the words of its operands, which a poison
// among them then gives up.
enum class Takes : std::uint8_t { Words, Nothing };

// The rewrite `rewriter` is applying a word pattern through: the pass
// applies them only with its own WordRewriter, as a conversion pattern's
// driver applies it only with a conversion rewriter.
WordRewriter &at(PatternRewriter &rewriter) { return static_cast<WordRewriter &>(rewriter); }

// Runs `narrow` on `op`, the op of the step the rewrite is at, as one
// action. When it narrows, `op` is gone: its results are the decisions'
// computed values, and, as `takes` says, the words of its operands are
// taken.
template <typename Narrow>
LogicalResult narrowed(WordRewriter &rewriter, Operation *op, Takes takes, Narrow &&narrow) {
  llvm::ArrayRef<ValueId> ids = rewriter.facts.idsOf(*rewriter.step);
  unsigned operands = op->getNumOperands();
  bool done = false;
  (void)support::perform<NarrowWordAction>(op, [&] { done = narrow(ids); });
  if (!done)
    return failure();
  for (ValueId v : ids.drop_front(operands))
    (void)rewriter.decided.computed.raise(v);
  if (takes == Takes::Words)
    for (ValueId v : ids.take_front(operands))
      (void)rewriter.decided.asked.raise(v);
  return success();
}

// Whether every big among `ids` fits.
bool allFit(const Facts &facts, llvm::ArrayRef<ValueId> ids) {
  return llvm::all_of(ids, [&](ValueId v) {
    return facts.carrier(v) == Carrier::NoBig || facts.fits(v);
  });
}

// Whether an op's operands and results may be negative.
enum class Sign : std::uint8_t { MayBeNegative, NotNegative };

// Whether anything among `ids` may be negative.
Sign signOf(const Facts &facts, llvm::ArrayRef<ValueId> ids) {
  return llvm::all_of(ids,
                      [&](ValueId v) {
                        ranges::Bounds b = facts.bounds(v);
                        return b.lo && *b.lo >= 0;
                      })
             ? Sign::NotNegative
             : Sign::MayBeNegative;
}

arith::IntegerOverflowFlags noWrap(Sign sign) {
  return sign == Sign::NotNegative
             ? arith::IntegerOverflowFlags::nsw | arith::IntegerOverflowFlags::nuw
             : arith::IntegerOverflowFlags::nsw;
}

// Replaces `op`'s big result by the big of `word`.
void replaceBig(RewriterBase &rewriter, Operation *op, Value word) {
  Value result = op->getResult(0);
  rewriter.replaceOp(op, big(rewriter, op->getLoc(), result.getType(), word));
}

// The word of what the big op `op` computes, on the words of its operands:
// the word op it names (BigToWord) applied to them and, where it names
// one, to its constant after them; the word itself where it names no op. A
// sum, difference or product carries no wrap, and none unsigned when
// nothing is negative; a comparison is its predicate on words, signed; a
// conversion to an integer narrower than the word truncates; the larger of
// a value that is not negative and 0 is the value.
template <typename OpT>
Value wordOf(RewriterBase &rewriter, OpT op, Sign sign) {
  using Word = typename BigToWord<OpT>::Op;
  Location loc = op.getLoc();
  SmallVector<Value> words;
  for (Value operand : op->getOperands())
    words.push_back(word(rewriter, loc, operand));
  auto constant = [&](int64_t value) {
    return arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(value));
  };
  if constexpr (std::is_void_v<Word>) {
    return words.front();
  } else if constexpr (std::is_same_v<Word, arith::CmpIOp>) {
    return arith::CmpIOp::create(rewriter, loc, layout::signedPredicate(op.getPredicate()),
                                 words[0], words[1]);
  } else if constexpr (std::is_same_v<Word, arith::TruncIOp>) {
    Type type = op.getType();
    return type == words.front().getType()
               ? words.front()
               : Value(arith::TruncIOp::create(rewriter, loc, type, words.front()));
  } else if constexpr (std::is_same_v<Word, arith::MaxSIOp>) {
    return sign == Sign::NotNegative
               ? words.front()
               : Value(arith::MaxSIOp::create(rewriter, loc, words.front(),
                                              constant(BigToWord<OpT>::constant)));
  } else {
    Value rhs;
    if constexpr (requires { BigToWord<OpT>::constant; })
      rhs = constant(BigToWord<OpT>::constant);
    else
      rhs = words[1];
    return Word::create(rewriter, loc, words.front(), rhs, noWrap(sign));
  }
}

// A big op whose word op the ODS names (BigToWord), when every big it
// takes and gives fits. What it took over the word takes nothing of, so
// the big it took drops its reference there.
template <typename OpT>
struct NarrowArith : OpRewritePattern<OpT> {
  using OpRewritePattern<OpT>::OpRewritePattern;

  LogicalResult matchAndRewrite(OpT op, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    return narrowed(rewriter, op.getOperation(), Takes::Words, [&](llvm::ArrayRef<ValueId> ids) {
      if (!allFit(rewriter.facts, ids))
        return false;
      rewriter.setInsertionPoint(op);
      Location loc = op.getLoc();
      Value made = wordOf(rewriter, op, signOf(rewriter.facts, ids));
      for (OpOperand &operand : op->getOpOperands())
        if (effects::consumes(operand) && owned(operand.get()))
          CountDropOp::create(rewriter, loc, operand.get());
      if (isBig(op->getResult(0).getType()))
        replaceBig(rewriter, op.getOperation(), made);
      else
        rewriter.replaceOp(op, made);
      return true;
    });
  }
};

// A guard's result is its guarded operand, so the guard of a big that fits
// guards its word, and its result is the big of the checked word. The
// guard took the big's reference; the word takes none, so the big drops
// it.
struct NarrowGuard : OpInterfaceRewritePattern<GuardOpInterface> {
  using OpInterfaceRewritePattern::OpInterfaceRewritePattern;

  LogicalResult matchAndRewrite(GuardOpInterface guard, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    Value guarded = guard.getGuarded();
    Operation *op = guard.getOperation();
    return narrowed(rewriter, op, Takes::Words, [&](llvm::ArrayRef<ValueId> ids) {
      if (!isBig(guarded.getType()) || !allFit(rewriter.facts, ids))
        return false;
      rewriter.setInsertionPoint(op);
      Location loc = op->getLoc();
      Value value = word(rewriter, loc, guarded);
      Operation *checked = rewriter.clone(*op);
      checked->setOperand(0, value);
      checked->getResult(0).setType(value.getType());
      if (owned(guarded))
        CountDropOp::create(rewriter, loc, guarded);
      replaceBig(rewriter, op, checked->getResult(0));
      return true;
    });
  }
};

// Counting a big made of a word counts nothing, since it holds no
// reference: each result of the op is the big of the same word, at its own
// type, and the op goes. Any other big proved small keeps its count ops:
// counting still tracks it (a call's result, a parameter), and on a small
// they do nothing at run time. The operand is made of a word where the walk
// met an idr.big.small, or where the rewrite has since put the big of a
// word in its place.
template <typename OpT>
struct NarrowCount : OpRewritePattern<OpT> {
  using OpRewritePattern<OpT>::OpRewritePattern;

  LogicalResult matchAndRewrite(OpT op, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    return narrowed(rewriter, op.getOperation(), Takes::Nothing, [&](llvm::ArrayRef<ValueId> ids) {
      ValueId value = ids.front();
      const Decisions &decided = rewriter.decided;
      bool madeOfWord = rewriter.facts.carrier(value) == Carrier::SmallBig ||
                        decided.carried.test(value) || decided.computed.test(value);
      if (rewriter.facts.carrier(value) == Carrier::NoBig || !madeOfWord ||
          !allFit(rewriter.facts, ids))
        return false;
      rewriter.setInsertionPoint(op);
      Location loc = op.getLoc();
      Value small = word(rewriter, loc, op->getOperand(0));
      rewriter.replaceOp(op, llvm::map_to_vector(op->getResults(), [&](Value result) {
                           return big(rewriter, loc, result.getType(), small);
                         }));
      return true;
    });
  }
};

// One NarrowArith rooted at each op of `OpTs`.
template <typename... OpTs>
void addArith(RewritePatternSet &patterns) {
  (patterns.add<NarrowArith<OpTs>>(patterns.getContext()), ...);
}

} // namespace

void populateWordPatterns(RewritePatternSet &patterns) {
  addArith<
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/Generated/BigToWord.h.inc"
      >(patterns);
  patterns.add<NarrowGuard, NarrowCount<CountDupOp>, NarrowCount<CountDropOp>>(
      patterns.getContext());
}

} // namespace idr::narrow
