// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it.
//
// The analysis is MLIR's, seeing our ops through their ranges
// (idr.ranges); this pass only reads it and rewrites. Nothing it
// learns is stored: the rewritten IR is the fact. A narrowed op becomes
// `arith` on the values, which idr.big.to_int and idr.big.from_int convert
// where the web meets a big it does not prove; the pairs they form inside
// a web fold away.

#include "Ownership/Ownership.h"
#include "idr/Idr.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/TypeSwitch.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROW
#include "idr/Passes.h.inc"
} // namespace idr

import idr.ranges;

using namespace mlir;
using namespace mlir::dataflow;
using namespace idr;

namespace {

using ranges::Bounds;

bool isBig(Type type) { return isa<BigType, NatType>(unrestricted(type)); }

// MLIR's analysis starts a value it cannot see computed at every value of
// its type; a natural's type proves more, that it is at least 0.
class NaturalRanges : public IntegerRangeAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NaturalRanges)
  using IntegerRangeAnalysis::IntegerRangeAnalysis;

  void setToEntryState(IntegerValueRangeLattice *lattice) override {
    if (isa<NatType>(lattice->getAnchor().getType())) {
      propagateIfChanged(lattice,
                         lattice->join(IntegerValueRange(ranges::rangeOf(ranges::natural()))));
      return;
    }
    IntegerRangeAnalysis::setToEntryState(lattice);
  }

  // Poison is no value: every range holds of it, so it adds nothing to the
  // range of a merge it flows into, as on the path out of a loop.
  LogicalResult visitOperation(Operation *op, ArrayRef<const IntegerValueRangeLattice *> operands,
                               ArrayRef<IntegerValueRangeLattice *> results) override {
    if (isa<ub::PoisonOp>(op))
      return success();
    return IntegerRangeAnalysis::visitOperation(op, operands, results);
  }
};

LogicalResult runSolver(DataFlowSolver &solver, Operation *root) {
  solver.load<DeadCodeAnalysis>();
  solver.load<SparseConstantPropagation>();
  solver.load<NaturalRanges>();
  return solver.initializeAndRun(root);
}

// Whether the big `value` holds a reference of its own, which a word
// taking its place in a consuming use leaves it to drop: once counting ran
// (`counted`), its grade says so, and a value that stands for one (a
// small big, poison) holds none.
bool ownedBig(Value value, bool counted) {
  return counted && isOwned(value.getType()) && !ownership::isStatic(value);
}

// The bounds of values: the analysis's, and those of the values the pass
// makes, which stand for values it analysed.
class Facts {
public:
  Facts(DataFlowSolver &s, bool counted) : solver(s), counted(counted) {}

  bool owned(Value value) const { return ownedBig(value, counted); }

  // Whether `value` is borrowed once counting ran: it is counted, and holds
  // no reference of its own.
  bool borrowed(Value value) const {
    return counted && !isOwned(value.getType()) && !ownership::isStatic(value);
  }

  Bounds of(Value value) const {
    // Poison may be taken to be any value, so a small one.
    if (value.getDefiningOp<ub::PoisonOp>())
      return {0, 0};
    if (auto it = made.find(value); it != made.end())
      return it->second;
    auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
    // Code the analysis never reached has no range, and proves nothing.
    if (!state || state->getValue().isUninitialized())
      return {};
    Bounds bounds = ranges::boundsOf(state->getValue().getValue());
    if (isa<NatType>(value.getType()) && bounds.hi && (!bounds.lo || *bounds.lo < 0))
      bounds.lo = 0;
    return bounds;
  }

  bool fits(Value value) const { return isBig(value.getType()) && of(value).fits(); }

  // Nothing among `values` is negative.
  bool nonNegative(ValueRange values) const {
    return llvm::all_of(values, [&](Value v) {
      Bounds b = of(v);
      return b.lo && *b.lo >= 0;
    });
  }

  // The word of the big `value`: the integer it was made of, when it was,
  // or its value converted.
  Value word(OpBuilder &b, Location loc, Value value) {
    auto i64 = b.getI64Type();
    if (auto poison = value.getDefiningOp<ub::PoisonOp>()) {
      // The big poison goes once nothing reads it.
      converted_.push_back(poison);
      return ub::PoisonOp::create(b, loc, i64);
    }
    if (auto small = value.getDefiningOp<BigSmallOp>())
      return small.getValue();
    if (auto from = value.getDefiningOp<BigFromIntOp>()) {
      Value source = from.getValue();
      if (source.getType() == i64)
        return source;
      return from.getIsSigned() ? Value(arith::ExtSIOp::create(b, loc, i64, source))
                                : Value(arith::ExtUIOp::create(b, loc, i64, source));
    }
    Value converted = BigToIntOp::create(b, loc, i64, value);
    converted_.push_back(converted.getDefiningOp());
    return converted;
  }

  // The big of type `type` whose value is `word`, with the bounds `bounds`,
  // which prove it small: it holds no reference, so counting skips it.
  Value big(OpBuilder &b, Location loc, Type type, Value word, Bounds bounds) {
    Value value = BigSmallOp::create(b, loc, type, word);
    made[value] = bounds;
    converted_.push_back(value.getDefiningOp());
    return value;
  }

  // The conversions made, for the folds that pair them.
  ArrayRef<Operation *> converted() const { return converted_; }

private:
  DataFlowSolver &solver;
  bool counted;
  DenseMap<Value, Bounds> made;
  SmallVector<Operation *> converted_;
};

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

//===----------------------------------------------------------------------===//
// Versioning
//===----------------------------------------------------------------------===//

// Whether `value` is `arg` or a predecessor of it, within one trip round the
// loop: through predecessors, the condition's forwarding, and every region
// of a merge.
bool descends(Value value, BlockArgument arg, scf::WhileOp loop, unsigned depth = 0) {
  if (depth > 64)
    return false;
  if (value == arg)
    return true;
  // What is yielded on the path out of the loop, and never comes back.
  if (value.getDefiningOp<ub::PoisonOp>())
    return true;
  if (auto pred = value.getDefiningOp<BigPredOp>())
    return descends(pred.getValue(), arg, loop, depth + 1);
  if (auto forwarded = dyn_cast<BlockArgument>(value)) {
    if (forwarded.getOwner() != &loop.getAfter().front())
      return false;
    return descends(loop.getConditionOp().getArgs()[forwarded.getArgNumber()], arg, loop,
                    depth + 1);
  }
  auto result = cast<OpResult>(value);
  Operation *merge = result.getOwner();
  if (merge->getNumRegions() == 0 || !isa<RegionBranchOpInterface>(merge))
    return false;
  return llvm::all_of(merge->getRegions(), [&](Region &region) {
    if (region.empty())
      return true;
    Operation *terminator = region.front().getTerminator();
    // A region that ends the program yields nothing.
    if (terminator->getNumOperands() != merge->getNumResults())
      return !isa<RegionBranchTerminatorOpInterface>(terminator);
    return descends(terminator->getOperand(result.getResultNumber()), arg, loop, depth + 1);
  });
}

// The first natural argument of `loop` that only descends and that the
// analysis does not already prove small, or none.
std::optional<unsigned> descendingArgument(scf::WhileOp loop, const Facts &facts) {
  // Once counting ran, a slot that carries a borrowed value passes it out of
  // the loop borrowed, which a branch between two copies of the loop would
  // have to take owned: such a loop stays one loop.
  if (llvm::any_of(loop.getInits(), [&](Value init) { return facts.borrowed(init); }))
    return std::nullopt;
  Block &before = loop.getBefore().front();
  auto yield = cast<scf::YieldOp>(loop.getAfter().front().getTerminator());
  for (BlockArgument arg : before.getArguments())
    if (isa<NatType>(arg.getType()) && !facts.fits(arg) &&
        descends(yield.getOperand(arg.getArgNumber()), arg, loop))
      return arg.getArgNumber();
  return std::nullopt;
}

// if (init <= smallMax) { the loop, from init masked to its low 62 bits }
// else { the loop }. On the first path the mask changes nothing, and shows
// the analysis the bound that a descending argument keeps.
void version(RewriterBase &rewriter, scf::WhileOp loop, unsigned index, bool counted) {
  Location loc = loop.getLoc();
  MLIRContext *ctx = loop.getContext();
  Value init = loop.getInits()[index];
  Type nat = init.getType();
  rewriter.setInsertionPoint(loop);
  std::string max = std::to_string(ranges::smallMax);
  Value bound = ConstantOp::create(rewriter, loc, nat, BigAttr::get(ctx, max));
  Value small = BigCmpOp::create(rewriter, loc, CmpPredicate::lte, init, bound);
  auto branch = scf::IfOp::create(rewriter, loc, loop.getResultTypes(), small,
                                  /*withElseRegion=*/true);
  rewriter.replaceAllUsesWith(loop.getResults(), branch.getResults());

  rewriter.setInsertionPointToStart(branch.thenBlock());
  Value word = BigToIntOp::create(rewriter, loc, rewriter.getI64Type(), init);
  Value mask = arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(ranges::smallMax));
  Value masked = arith::AndIOp::create(rewriter, loc, word, mask);
  Value start = BigSmallOp::create(rewriter, loc, nat, masked);
  // The copy starts from the word, so the natural it was read from drops
  // the reference the loop would have taken.
  if (ownedBig(init, counted))
    DropOp::create(rewriter, loc, init);
  Operation *copy = rewriter.clone(*loop);
  rewriter.modifyOpInPlace(copy, [&] { copy->setOperand(index, start); });
  scf::YieldOp::create(rewriter, loc, copy->getResults());

  rewriter.setInsertionPointToStart(branch.elseBlock());
  auto otherwise = scf::YieldOp::create(rewriter, loc, loop.getResults());
  rewriter.moveOpBefore(loop, otherwise);
}

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    IRRewriter rewriter(&getContext());
    auto stage = module->getAttrOfType<StringAttr>(ownership::stageAttr);
    bool counted = stage && stage.getValue() == ownership::ownedStage;
    {
      DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
      if (failed(runSolver(solver, module)))
        return signalPassFailure();
      Facts facts(solver, counted);
      SmallVector<std::pair<scf::WhileOp, unsigned>> versions;
      module.walk([&](scf::WhileOp loop) {
        if (std::optional<unsigned> index = descendingArgument(loop, facts))
          versions.emplace_back(loop, *index);
      });
      for (auto [loop, index] : versions)
        version(rewriter, loop, index, counted);
      numVersioned += versions.size();
    }

    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    if (failed(runSolver(solver, module)))
      return signalPassFailure();
    Facts facts(solver, counted);
    // The joints first, while every value is still the one analysed; then
    // the ops, whose operands may by then be the bigs of words.
    SmallVector<Operation *> joints, ops;
    module.walk([&](Operation *op) {
      if (isa<scf::WhileOp, scf::ForOp, scf::IfOp, scf::IndexSwitchOp, MatchOp, MatchLitOp>(op))
        joints.push_back(op);
      if (isa<MatchLitOp, BigAddOp, BigSubOp, BigMulOp, BigPredOp, BigCmpOp, NatFromBigOp, NatToBigOp,
                   BigToIntOp, DupOp, DropOp>(op))
        ops.push_back(op);
    });
    for (Operation *op : joints)
      numCarried += narrowCarried(rewriter, facts, op);
    for (Operation *op : ops)
      if (narrowOp(rewriter, facts, op))
        ++numNarrowed;

    // A word made a big and back is the word; what no one reads goes.
    GreedyRewriteConfig config;
    config.setStrictness(GreedyRewriteStrictness::ExistingAndNewOps);
    (void)applyOpPatternsGreedily(facts.converted(), FrozenRewritePatternSet(), config);
    // A versioned loop's start, once its copy took the word, and a big
    // made of a word that every reader now takes as the word.
    module.walk([&](Operation *op) {
      if (isa<BigSmallOp, BigFromIntOp>(op) && isOpTriviallyDead(op))
        rewriter.eraseOp(op);
    });
  }
};

} // namespace
