// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op whose bigs all fit made an op on words. Each pattern is rooted at
// its op, so MLIR finds the one for the op the rewrite is at; it decides on
// the numbers of what the op took and gave as the walk met it, which the
// bigs standing in for them share, and then rewrites. A literal match is a
// joint, met as the walk enters it, before anything its regions hold.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/CastInterfaces.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"

// The word op of each big op that names one: BigToWord.
#include "idr/IR/Generated/BigToWord.h.inc"

#include <cassert>
#include <cstdint>
#include <optional>
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

// Replaces `op`'s big result by the small of `word`.
void replaceBig(WordRewriter &rewriter, Operation *op, Value word) {
  Value result = op->getResult(0);
  rewriter.replaceOp(op, rewriter.standIn(op->getLoc(), result.getType(), word));
}

// The word of what the big op `op` computes, on the words of its operands,
// each read from what `read` holds for it: the word op it names
// (BigToWord) applied to them as the ODS says that op takes them and, where
// the big op names a constant, to it after them; the word itself where it
// names no op, and where the big op leaves a natural as it is
// (LeavesNaturals) and nothing is negative. A conversion (CastOpInterface)
// to an integer narrower than the word truncates; a comparison is the big
// op's predicate on words, signed; a sum, difference or product
// (ArithIntegerOverflowFlagsInterface) carries no wrap, and none unsigned
// when nothing is negative.
template <typename OpT>
Value wordOf(RewriterBase &rewriter, OpT op, llvm::ArrayRef<Replaced> read, Sign sign) {
  using Word = typename BigToWord<OpT>::Op;
  Location loc = op.getLoc();
  SmallVector<Value> words;
  for (const Replaced &operand : read)
    words.push_back(word(rewriter, loc, operand.read));
  if constexpr (OpT::template hasTrait<LeavesNaturals>())
    if (sign == Sign::NotNegative)
      return words.front();
  if constexpr (std::is_void_v<Word>) {
    return words.front();
  } else if constexpr (Word::template hasTrait<CastOpInterface::Trait>()) {
    Type type = op.getType();
    return type == words.front().getType()
               ? words.front()
               : Value(Word::create(rewriter, loc, type, words.front()));
  } else if constexpr (requires { op.getPredicate(); }) {
    return Word::create(rewriter, loc, layout::signedPredicate(op.getPredicate()), words[0],
                        words[1]);
  } else {
    Value rhs;
    if constexpr (requires { BigToWord<OpT>::constant; })
      rhs = arith::ConstantOp::create(rewriter, loc,
                                      rewriter.getI64IntegerAttr(BigToWord<OpT>::constant));
    else
      rhs = words[1];
    if constexpr (Word::template hasTrait<arith::ArithIntegerOverflowFlagsInterface::Trait>())
      return Word::create(rewriter, loc, words.front(), rhs, noWrap(sign));
    else
      return Word::create(rewriter, loc, words.front(), rhs);
  }
}

// A big op whose word op the ODS names (BigToWord), when every big it
// takes and gives fits. What it took over the word takes nothing of, so
// the big it took gives its reference up there.
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
      SmallVector<Replaced> bigs = llvm::map_to_vector(
          op->getOpOperands(), [&](OpOperand &operand) { return replace(rewriter, loc, operand); });
      Value made = wordOf(rewriter, op, bigs, signOf(rewriter.facts, ids));
      for (const Replaced &big : bigs)
        giveUp(rewriter, loc, big);
      if (isCarriedAsBig(op->getResult(0).getType()))
        replaceBig(rewriter, op.getOperation(), made);
      else
        rewriter.replaceOp(op, made);
      return true;
    });
  }
};

// A guard's result is its guarded operand, its first, so the guard of a big
// that fits guards its word, and its result is the small of the checked
// word. The guard took the big's reference; the word takes none, so the big
// gives it up.
struct NarrowGuard : OpInterfaceRewritePattern<GuardOpInterface> {
  using OpInterfaceRewritePattern::OpInterfaceRewritePattern;

  LogicalResult matchAndRewrite(GuardOpInterface guard, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    Operation *op = guard.getOperation();
    OpOperand &guarded = op->getOpOperand(0);
    assert(guarded.get() == guard.getGuarded() && "a guard's guarded value is its first operand");
    return narrowed(rewriter, op, Takes::Words, [&](llvm::ArrayRef<ValueId> ids) {
      if (!isCarriedAsBig(guarded.get().getType()) || !allFit(rewriter.facts, ids))
        return false;
      rewriter.setInsertionPoint(op);
      Location loc = op->getLoc();
      Replaced big = replace(rewriter, loc, guarded);
      Value value = word(rewriter, loc, big.read);
      Operation *checked = rewriter.clone(*op);
      checked->setOperand(0, value);
      checked->getResult(0).setType(value.getType());
      giveUp(rewriter, loc, big);
      replaceBig(rewriter, op, checked->getResult(0));
      return true;
    });
  }
};

// Counting a big the rewrite put a small in the place of counts nothing,
// since a small holds no reference: each result of the op is the small of
// the same word, standing for the big of its own type, and the op goes.
// Any other big proved small keeps its count ops: counting still tracks it
// (a call's result, a parameter), and on a small they do nothing at run
// time.
template <typename OpT>
struct NarrowCount : OpRewritePattern<OpT> {
  using OpRewritePattern<OpT>::OpRewritePattern;

  LogicalResult matchAndRewrite(OpT op, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    return narrowed(rewriter, op.getOperation(), Takes::Nothing, [&](llvm::ArrayRef<ValueId> ids) {
      ValueId value = ids.front();
      const Decisions &decided = rewriter.decided;
      bool madeOfWord = decided.carried.test(value) || decided.computed.test(value);
      if (rewriter.facts.carrier(value) == Carrier::NoBig || !madeOfWord ||
          !allFit(rewriter.facts, ids))
        return false;
      rewriter.setInsertionPoint(op);
      Location loc = op.getLoc();
      Value madeOf = word(rewriter, loc, op->getOperand(0));
      rewriter.replaceOp(op, llvm::map_to_vector(op->getResults(), [&](Value result) {
                           return rewriter.standIn(loc, result.getType(), madeOf);
                         }));
      return true;
    });
  }
};

// A literal match on a big matches its word when every key is a word and
// the value its default binds, the scrutinee none of the keys, fits a
// small: the scrutinee is then a word wherever the match reads it, a key in
// each case and that value in the default. Its keys become words, and
// every region binds the word, whose uses read the small of it, which holds
// no reference. The match forwards its scrutinee into each region's
// binding, which moves a counted big's reference on, and the word it then
// matches takes nothing of it, so the big gives it up before the match.
// The bound asked is the default's binding, a value of the joint the walk
// numbered, as the rewrite enters the joint before any op of its regions is
// rewritten.
struct NarrowLiteralMatch : OpRewritePattern<LitMatchOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(LitMatchOp match, PatternRewriter &base) const override {
    WordRewriter &rewriter = at(base);
    Value scrutinee = match.getScrutinee();
    if (!isCarriedAsBig(scrutinee.getType()))
      return failure();
    BlockArgument refined = match.getDefaultRegion().getArgument(0);
    if (!rewriter.facts.fits(rewriter.facts.at(refined)))
      return failure();
    // A big's and a natural's keys are big literals, as their types say.
    // Each must be a small, since the case that takes it binds its small.
    SmallVector<Attribute> keys;
    for (Attribute key : match.getCases()) {
      std::optional<int64_t> value = cast<BigAttr>(key).getValue().trySExtValue();
      if (!value || !ranges::bounded(*value, *value).fits())
        return failure();
      keys.push_back(rewriter.getI64IntegerAttr(*value));
    }
    // Each region binds the scrutinee at its position, whose lifetime the
    // match states once for every region, the last it states, where the
    // binding is a view; a word lives in none.
    SmallVector<Value> outers(match.getOuters());
    if (borrowed(refined))
      outers.pop_back();
    SmallVector<BlockArgument> bindings = llvm::map_to_vector(
        match->getRegions(), [](Region &region) { return region.getArgument(0); });
    bool done = support::perform<NarrowWordAction>(match, [&] {
      rewriter.setInsertionPoint(match);
      Location loc = match.getLoc();
      Replaced big = replace(rewriter, loc, match.getScrutineeMutable());
      Value word = narrow::word(rewriter, loc, big.read);
      giveUp(rewriter, loc, big);
      rewriter.modifyOpInPlace(match, [&] {
        match.getScrutineeMutable().set(word);
        match.setCasesAttr(rewriter.getArrayAttr(keys));
        lifetimes::restateOuters(cast<StatesOutersOpInterface>(match.getOperation()), outers);
      });
      for (BlockArgument binding : bindings)
        narrowArgument(rewriter, binding);
    });
    if (!done)
      return failure();
    // Each binding is now made of a word, so counting it counts nothing.
    for (BlockArgument binding : bindings)
      (void)rewriter.decided.computed.raise(rewriter.facts.at(binding));
    return success();
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
  patterns.add<NarrowGuard, NarrowCount<CountDupOp>, NarrowCount<CountDropOp>,
               NarrowLiteralMatch>(patterns.getContext());
}

} // namespace idr::narrow
