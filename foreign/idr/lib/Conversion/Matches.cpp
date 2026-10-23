// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lowering of the control-flow ops (Matches.h): matches to scf on idr
// types, the join points' types converted, then every region to blocks in
// one conversion with upstream's scf patterns.

#include "idr/Conversion/Matches.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <type_traits>

using namespace mlir;

namespace idr::conversion {

namespace {

//===----------------------------------------------------------------------===//
// Phase 1
//===----------------------------------------------------------------------===//

// Moves the body of `from` into `into`, a new block of the scf op that
// replaces the match; `args` stand for the body's arguments. An idr.yield
// becomes scf.yield; a jump, or a terminator that never ends, stays, as the
// scf ops hold it. The terminator is replaced while it is still the
// match's, which the walk driver lets a pattern erase.
void moveBody(RewriterBase &rewriter, Region &from, Block *into, ValueRange args) {
  if (auto yield = dyn_cast<YieldOp>(from.front().getTerminator())) {
    rewriter.setInsertionPoint(yield);
    rewriter.replaceOpWithNewOp<scf::YieldOp>(yield, yield.getResults());
  }
  rewriter.mergeBlocks(&from.front(), into, args);
}

// A case's arguments at the end of `into`: the scrutinee and each
// forwarded value at the type the case binds it at, a refinement with no
// run-time form, which the conversion of types then folds away.
SmallVector<Value> refinedArgs(RewriterBase &rewriter, Region &region, Block *into,
                               ValueRange entering) {
  rewriter.setInsertionPointToEnd(into);
  SmallVector<Value> args;
  for (auto [arg, value] : llvm::zip_equal(region.getArguments(), entering)) {
    if (arg.getType() == value.getType()) {
      args.push_back(value);
      continue;
    }
    args.push_back(
        UnrealizedConversionCastOp::create(rewriter, arg.getLoc(), arg.getType(), value)
            .getResult(0));
  }
  return args;
}

// The tag selects the case. An exhaustive match's empty default leaves its
// last case as the switch's default, which is not tested for: a match may be
// exhaustive, a switch may not; a match left with one region reads no tag.
void lowerMatch(RewriterBase &rewriter, DataMatchOp op) {
  Location loc = op.getLoc();
  rewriter.setInsertionPoint(op);
  SmallVector<Region *> cases;
  SmallVector<int64_t> tags;
  for (auto [tag, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    cases.push_back(&region);
    tags.push_back(static_cast<uint32_t>(tag));
  }
  Region *fallback = &op.getDefaultRegion();
  if (fallback->empty()) {
    fallback = cases.pop_back_val();
    tags.pop_back();
  }
  Value index;
  if (tags.empty()) {
    index = arith::ConstantIndexOp::create(rewriter, loc, 0);
  } else {
    Value scrutinee =
        heldAs(rewriter, loc, op.getScrutinee(), unrestricted(op.getScrutinee().getType()));
    Value tag = DataTagOp::create(rewriter, loc, scrutinee);
    index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), tag);
  }
  auto switchOp = scf::IndexSwitchOp::create(rewriter, loc, op.getResultTypes(), index, tags,
                                             static_cast<unsigned>(tags.size()));
  ValueRange entering = op.getEntering();
  for (auto [region, to] : llvm::zip_equal(cases, switchOp.getCaseRegions())) {
    Block *into = rewriter.createBlock(&to);
    moveBody(rewriter, *region, into, refinedArgs(rewriter, *region, into, entering));
  }
  Block *into = rewriter.createBlock(&switchOp.getDefaultRegion());
  moveBody(rewriter, *fallback, into, refinedArgs(rewriter, *fallback, into, entering));
  rewriter.replaceOp(op, switchOp.getResults());
}

// A key's test: the condition that the scrutinee is `key`, made where the
// rewriter stands.
template <typename Test>
concept KeyTest = std::is_invocable_r_v<Value, Test &, Location, Attribute>;

// `case k0 {A} case k1 {B} default(%d) {C}` is `if s == k0 then A else (if
// s == k1 then B else C[%d := s])`, each comparison made only where the one
// before failed. The chain is built in the block of a scaffold made where the
// match is: every link is made at the end of the block it continues, which
// yields the link's results, and the link's else block is the next block
// continued. The default ends the last block continued. The scaffold's
// block then takes the match's place.
template <KeyTest Test>
void lowerChain(RewriterBase &rewriter, LitMatchOp op, Test test) {
  Location loc = op.getLoc();
  TypeRange results = op.getResultTypes();
  rewriter.setInsertionPoint(op);
  auto scaffold = scf::ExecuteRegionOp::create(rewriter, loc, results);
  Block *continued = rewriter.createBlock(&scaffold.getRegion());
  for (auto [key, region] : llvm::zip_equal(op.getCases(), op.getCaseRegions())) {
    rewriter.setInsertionPointToEnd(continued);
    Value equal = test(loc, key);
    auto link = scf::IfOp::create(rewriter, loc, results, equal, /*addThenBlock=*/false,
                                  /*addElseBlock=*/false);
    scf::YieldOp::create(rewriter, loc, link.getResults());
    moveBody(rewriter, region, rewriter.createBlock(&link.getThenRegion()), ValueRange());
    continued = rewriter.createBlock(&link.getElseRegion());
  }
  moveBody(rewriter, op.getDefaultRegion(), continued, op.getScrutinee());
  Block *chain = &scaffold.getRegion().front();
  Operation *last = chain->getTerminator();
  rewriter.inlineBlockBefore(chain, op);
  if (auto yield = dyn_cast<scf::YieldOp>(last)) {
    rewriter.replaceOp(op, yield.getResults());
    rewriter.eraseOp(yield);
  } else {
    // With no case, the default's own end is the chain's: a jump, or one
    // that never ends, after which nothing of the match's results is read.
    rewriter.eraseOp(op);
  }
  rewriter.eraseOp(scaffold);
}

// A word is switched on: scf.index_switch compares the word's index cast
// with each key, sign-extended as the cast extends the word, and the
// default is handed the scrutinee. The refinement the default binds and the
// lifetimes the match states have no run-time form, and go with it.
void switchOnWord(RewriterBase &rewriter, LitMatchOp op, Value word) {
  Location loc = op.getLoc();
  Value index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), word);
  SmallVector<int64_t> keys = llvm::map_to_vector(op.getCases(), [](Attribute key) {
    return cast<IntegerAttr>(key).getValue().getSExtValue();
  });
  auto switchOp = scf::IndexSwitchOp::create(rewriter, loc, op.getResultTypes(), index, keys,
                                             static_cast<unsigned>(keys.size()));
  for (auto [region, to] : llvm::zip_equal(op.getCaseRegions(), switchOp.getCaseRegions()))
    moveBody(rewriter, region, rewriter.createBlock(&to), ValueRange());
  moveBody(rewriter, op.getDefaultRegion(), rewriter.createBlock(&switchOp.getDefaultRegion()),
           op.getScrutinee());
  rewriter.replaceOp(op, switchOp.getResults());
}

// Each carrier's keys are tested with its own equality. Essential: the
// equality of a word, a double, a string and a big are four ops. A word the
// target's index holds is switched on, and one wider is tested key by key;
// a double is tested by ordered equality, under which no key is NaN; a
// natural is a big at run time.
void lowerMatchLit(RewriterBase &rewriter, LitMatchOp op) {
  Location loc = op.getLoc();
  Value scrutinee = op.getScrutinee();
  Type carrier = unrestricted(scrutinee.getType());
  rewriter.setInsertionPoint(op);
  if (auto word = dyn_cast<IntegerType>(carrier)) {
    Value held = heldAs(rewriter, loc, scrutinee, carrier);
    llvm::TypeSize index = DataLayout::closest(op).getTypeSizeInBits(rewriter.getIndexType());
    if (word.getWidth() <= index.getFixedValue())
      return switchOnWord(rewriter, op, held);
    return lowerChain(rewriter, op, [&](Location at, Attribute key) -> Value {
      Value literal = arith::ConstantOp::create(rewriter, at, cast<TypedAttr>(key));
      return arith::CmpIOp::create(rewriter, at, arith::CmpIPredicate::eq, held, literal);
    });
  }
  if (isa<Float64Type>(carrier)) {
    Value held = heldAs(rewriter, loc, scrutinee, carrier);
    return lowerChain(rewriter, op, [&](Location at, Attribute key) -> Value {
      Value literal = arith::ConstantOp::create(rewriter, at, cast<TypedAttr>(key));
      return arith::CmpFOp::create(rewriter, at, arith::CmpFPredicate::OEQ, held, literal);
    });
  }
  if (isa<StrType>(carrier))
    return lowerChain(rewriter, op, [&](Location at, Attribute key) -> Value {
      Value literal = ConstantOp::create(rewriter, at, scrutinee.getType(), key);
      return StrCmpOp::create(rewriter, at, scrutinee, literal, CmpPredicate::eq);
    });
  lowerChain(rewriter, op, [&](Location at, Attribute key) -> Value {
    Value literal = ConstantOp::create(rewriter, at, scrutinee.getType(), key);
    return BigCmpOp::create(rewriter, at, scrutinee, literal, CmpPredicate::eq);
  });
}

struct LowerMatch : OpRewritePattern<DataMatchOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(DataMatchOp op, PatternRewriter &rewriter) const override {
    lowerMatch(rewriter, op);
    return success();
  }
};

struct LowerMatchLit : OpRewritePattern<LitMatchOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(LitMatchOp op, PatternRewriter &rewriter) const override {
    lowerMatchLit(rewriter, op);
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Phase 2
//===----------------------------------------------------------------------===//

SmallVector<Value> flatten(ArrayRef<ValueRange> values) {
  SmallVector<Value> flat;
  for (ValueRange range : values)
    llvm::append_range(flat, range);
  return flat;
}

// A join point's op with its results' and its regions' arguments converted,
// one value to its components; its regions moved into the new op, which
// states no lifetime: what it makes is lowered, and no longer scoped.
template <typename Group>
struct ConvertGroupTypes : OpConversionPattern<Group> {
  using OpConversionPattern<Group>::OpConversionPattern;
  using OneToNOpAdaptor = typename OpConversionPattern<Group>::OneToNOpAdaptor;

  LogicalResult matchAndRewrite(Group op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const TypeConverter &converter = *this->getTypeConverter();
    SmallVector<Type> types;
    SmallVector<unsigned> offsets{0};
    for (Value result : op->getResults()) {
      if (failed(converter.convertType(result.getType(), types)))
        return rewriter.notifyMatchFailure(op, "a result's type has no conversion");
      offsets.push_back(static_cast<unsigned>(types.size()));
    }
    for (Region &region : op->getRegions())
      if (failed(rewriter.convertRegionTypes(&region, converter)))
        return rewriter.notifyMatchFailure(op, "a region's arguments have no conversion");
    OperationState state(op.getLoc(), Group::getOperationName(), ValueRange(), types);
    state.getOrAddProperties<typename Group::Properties>().binders = op.getBinders();
    for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
      state.addRegion();
    Operation *fresh = rewriter.create(state);
    for (auto [from, into] : llvm::zip_equal(op->getRegions(), fresh->getRegions()))
      rewriter.inlineRegionBefore(from, into, into.end());
    SmallVector<ValueRange> packed;
    for (unsigned i = 1, e = static_cast<unsigned>(offsets.size()); i < e; ++i)
      packed.push_back(fresh->getResults().slice(offsets[i - 1], offsets[i] - offsets[i - 1]));
    rewriter.replaceOpWithMultiple(op, packed);
    return success();
  }
};

struct ConvertJumpTypes : OpConversionPattern<JumpOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(JumpOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<JumpOp>(op, llvm::getSingleElement(adaptor.getTarget()),
                                        flatten(adaptor.getArgs()),
                                        op.getTermsAttr());
    return success();
  }
};

// After phase 1 every idr.yield left ends a join point's region.
struct ConvertGroupYieldTypes : OpConversionPattern<YieldOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(YieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<YieldOp>(op, flatten(adaptor.getOperands()));
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Phase 3
//===----------------------------------------------------------------------===//

// The join points' op as blocks. Its regions are legalized first, so every
// match and every inner join point in them is blocks already, and every
// jump to this op and every yield of it ends a block of its regions; a jump
// to an enclosing op stays for that op's lowering.
template <typename Group>
struct LowerGroup : OpConversionPattern<Group> {
  using OpConversionPattern<Group>::OpConversionPattern;
  void initialize() { this->setHasBoundedRewriteRecursion(); }

  LogicalResult matchAndRewrite(Group op, typename OpConversionPattern<Group>::OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    for (Region &region : op->getRegions()) {
      OpBuilder::InsertionGuard guard(rewriter);
      if (failed(rewriter.legalize(&region)))
        return rewriter.notifyMatchFailure(op, "a region did not lower");
    }
    Location loc = op.getLoc();
    auto points = cast<JoinPointsOpInterface>(op.getOperation());
    SmallVector<Block *> entries;
    SmallVector<unsigned> tokens;
    SmallVector<YieldOp> yields;
    // Each jump to this op with its target's entry block, read while the
    // tokens are still the regions' own.
    SmallVector<std::pair<JumpOp, Block *>> jumps;
    for (Region &region : op->getRegions()) {
      entries.push_back(&region.front());
      tokens.push_back(static_cast<unsigned>(points.getTokens(region).size()));
    }
    // Essential: a block leaves by a yield of this op, which gives its
    // results, or by a jump, which names its join region by its token,
    // each read through its own op's accessors; every other end (a branch
    // between the blocks the regions became, one that never ends, a jump to
    // an enclosing op) stays.
    for (Region &region : op->getRegions())
      for (Block &block : region) {
        Operation *terminator = block.getTerminator();
        if (auto yield = dyn_cast<YieldOp>(terminator)) {
          yields.push_back(yield);
          continue;
        }
        auto jump = dyn_cast<JumpOp>(terminator);
        auto token = jump ? cast<BlockArgument>(jump.getTarget()) : BlockArgument();
        if (token && token.getOwner()->getParentOp() == op)
          jumps.emplace_back(jump, entries[points.getTarget(token)->getRegionNumber()]);
      }
    Block *before = rewriter.getInsertionBlock();
    Block *after = rewriter.splitBlock(before, rewriter.getInsertionPoint());
    after->addArguments(op->getResultTypes(),
                        SmallVector<Location>(op->getNumResults(), loc));
    for (Region &region : op->getRegions())
      rewriter.inlineRegionBefore(region, after);
    for (YieldOp yield : yields) {
      rewriter.setInsertionPoint(yield);
      cf::BranchOp::create(rewriter, yield.getLoc(), after, yield.getResults());
      rewriter.eraseOp(yield);
    }
    for (auto [jump, entry] : jumps) {
      rewriter.setInsertionPoint(jump);
      cf::BranchOp::create(rewriter, jump.getLoc(), entry, jump.getArgs());
      jump->setOperands({});
      rewriter.eraseOp(jump);
    }
    for (auto [entry, leading] : llvm::zip_equal(entries, tokens))
      entry->eraseArguments(0, leading);
    rewriter.setInsertionPointToEnd(before);
    cf::BranchOp::create(rewriter, loc, entries.front(), ValueRange());
    rewriter.replaceOp(op, after->getArguments());
    return success();
  }
};

} // namespace

void populateMatchPatterns(RewritePatternSet &patterns) {
  patterns.add<LowerMatch, LowerMatchLit>(patterns.getContext());
}

void populateJoinTypeConversions(const TypeConverter &converter, RewritePatternSet &patterns,
                                 ConversionTarget &target) {
  patterns.add<ConvertGroupTypes<JoinOp>, ConvertGroupTypes<LoopOp>, ConvertJumpTypes,
               ConvertGroupYieldTypes>(converter, patterns.getContext());
  // A join point's op is legal once its types are and it states no
  // lifetime, its operands being only those it states.
  auto groupLegal = [&converter](Operation *op) {
    return op->getNumOperands() == 0 && converter.isLegal(op->getResultTypes()) &&
           llvm::all_of(op->getRegions(), [&](Region &region) {
             return converter.isLegal(region.getArgumentTypes());
           });
  };
  target.addDynamicallyLegalOp<JoinOp, LoopOp>(groupLegal);
  target.addDynamicallyLegalOp<JumpOp>(
      [&converter](JumpOp op) { return converter.isLegal(op->getOperandTypes()); });
  target.addDynamicallyLegalOp<YieldOp>(
      [&converter](YieldOp op) { return converter.isLegal(op->getOperandTypes()); });
}

ControlFlowLowering::ControlFlowLowering(MLIRContext &context) : target(context) {
  RewritePatternSet set(&context);
  populateSCFToControlFlowConversionPatterns(set);
  set.add<LowerGroup<JoinOp>, LowerGroup<LoopOp>>(&context);
  patterns = FrozenRewritePatternSet(std::move(set));
  target.addIllegalOp<scf::ForallOp, scf::ForOp, scf::IfOp, scf::IndexSwitchOp, scf::LoopOp,
                      scf::ParallelOp, scf::WhileOp, scf::ExecuteRegionOp, JoinOp, LoopOp>();
  target.markUnknownOpDynamicallyLegal([](Operation *) { return true; });
}

LogicalResult lowerControlFlow(Operation *root, const ControlFlowLowering &lowering) {
  return applyPartialConversion(root, lowering.target, lowering.patterns);
}

} // namespace idr::conversion
