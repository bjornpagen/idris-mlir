// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lowering of the control-flow ops (Matches.h): matches to scf on idr
// types, the join points' types converted, then every region to blocks in
// one conversion with upstream's scf patterns, each loop that makes
// progress told so on its jumps back first.

#include "idr/Conversion/Matches.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Conversion/SCFToControlFlow/SCFToControlFlow.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/DataLayoutInterfaces.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cstdint>
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

// `case k0(%a) {A} case k1(%b) {B} default(%d) {C}` is `if s == k0 then
// A[%a := s] else (if s == k1 then B[%b := s] else C[%d := s])`, each
// comparison made only where the one before failed: every region's binding
// is the scrutinee, which has no other run-time form. The chain is built in the block of a scaffold made where the
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
    moveBody(rewriter, region, rewriter.createBlock(&link.getThenRegion()), op.getScrutinee());
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
// with each key, sign-extended as the cast extends the word, and every
// region is handed the scrutinee for its binding. The refinement the
// default binds and the lifetimes the match states have no run-time form,
// and go with it.
void switchOnWord(RewriterBase &rewriter, LitMatchOp op, Value word) {
  Location loc = op.getLoc();
  Value index = arith::IndexCastOp::create(rewriter, loc, rewriter.getIndexType(), word);
  SmallVector<int64_t> keys = llvm::map_to_vector(op.getCases(), [](Attribute key) {
    return cast<IntegerAttr>(key).getValue().getSExtValue();
  });
  auto switchOp = scf::IndexSwitchOp::create(rewriter, loc, op.getResultTypes(), index, keys,
                                             static_cast<unsigned>(keys.size()));
  for (auto [region, to] : llvm::zip_equal(op.getCaseRegions(), switchOp.getCaseRegions()))
    moveBody(rewriter, region, rewriter.createBlock(&to), op.getScrutinee());
  moveBody(rewriter, op.getDefaultRegion(), rewriter.createBlock(&switchOp.getDefaultRegion()),
           op.getScrutinee());
  rewriter.replaceOp(op, switchOp.getResults());
}

// Each carrier's keys are tested with its own equality, the test its type
// builds (LiteralTypeInterface::buildKeyTest). The scrutinee is held once:
// a value that holds no reference (a word, a double) as its plain value,
// which arith compares; one that holds references (a string, a big, a
// natural) read in place at its grade, which a cast would claim or forget.
// Essential, the two ways a value is read. A word the target's index holds
// is switched on, scf.index_switch taking an index; any other carrier is
// tested key by key.
void lowerMatchLit(RewriterBase &rewriter, LitMatchOp op) {
  Location loc = op.getLoc();
  Value scrutinee = op.getScrutinee();
  Type carrier = unrestricted(scrutinee.getType());
  rewriter.setInsertionPoint(op);
  Value held = holdsReferences(carrier) ? scrutinee : heldAs(rewriter, loc, scrutinee, carrier);
  if (auto word = dyn_cast<IntegerType>(carrier)) {
    llvm::TypeSize index = DataLayout::closest(op).getTypeSizeInBits(rewriter.getIndexType());
    if (word.getWidth() <= index.getFixedValue())
      return switchOnWord(rewriter, op, held);
  }
  auto literals = cast<LiteralTypeInterface>(carrier);
  lowerChain(rewriter, op, [&](Location at, Attribute key) {
    return literals.buildKeyTest(rewriter, at, held, key);
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
template <JoinFamily Group>
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
template <JoinFamily Group>
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
    SmallVector<Block *> entries;
    SmallVector<unsigned> tokens;
    for (Region &region : op->getRegions()) {
      entries.push_back(&region.front());
      tokens.push_back(static_cast<unsigned>(op.getTokens(region).size()));
    }
    // Each exit of this op's own, read while the tokens are still the
    // regions' own. Where control goes when a block ends is its
    // terminator's answer (upstream's region-branch terminator): an exit of
    // this op leaves for one of its successors, after the op with its
    // results (a yield) or into a join region with that region's parameters
    // (a jump to it). Every other end stays: a branch between the blocks the
    // regions became, one that never ends, an exit through this op to an
    // enclosing one, which that op's lowering reads.
    struct Exit {
      RegionBranchTerminatorOpInterface terminator;
      RegionSuccessor successor;
    };
    SmallVector<Exit> exits;
    for (Region &region : op->getRegions())
      for (Block &block : region) {
        auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(block.getTerminator());
        if (!terminator)
          continue;
        SmallVector<RegionSuccessor, 1> successors;
        terminator.getSuccessorRegions(SmallVector<Attribute>(terminator->getNumOperands()),
                                       successors);
        RegionSuccessor successor = llvm::getSingleElement(successors);
        if (getRegionBranchSuccessorOwner(successor).getOperation() == op.getOperation())
          exits.push_back({terminator, successor});
      }
    Block *before = rewriter.getInsertionBlock();
    Block *after = rewriter.splitBlock(before, rewriter.getInsertionPoint());
    after->addArguments(op->getResultTypes(),
                        SmallVector<Location>(op->getNumResults(), loc));
    for (Region &region : op->getRegions())
      rewriter.inlineRegionBefore(region, after);
    // Each exit a branch with what it passes, to the block after the op or
    // to its join region's entry, upstream's two successors; its own
    // operands are dropped before it goes, so a jump's token goes with its
    // region's leading arguments. What a jump carries for LLVM, the
    // annotation that its loop makes progress, goes on the branch it
    // becomes, where upstream's lowering of branches reads it.
    for (Exit &leaving : exits) {
      Block *into = leaving.successor.isOperation()
                        ? after
                        : entries[leaving.successor.getSuccessor()->getRegionNumber()];
      rewriter.setInsertionPoint(leaving.terminator);
      auto branch =
          cf::BranchOp::create(rewriter, leaving.terminator.getLoc(), into,
                               leaving.terminator.getSuccessorOperands(leaving.successor));
      if (!leaving.terminator->getDiscardableAttrs().empty())
        branch->setDiscardableAttrs(leaving.terminator->getDiscardableAttrDictionary());
      leaving.terminator->setOperands({});
      rewriter.eraseOp(leaving.terminator);
    }
    for (auto [entry, leading] : llvm::zip_equal(entries, tokens))
      entry->eraseArguments(0, leading);
    rewriter.setInsertionPointToEnd(before);
    cf::BranchOp::create(rewriter, loc, entries.front(), ValueRange());
    rewriter.replaceOp(op, after->getArguments());
    return success();
  }
};

// Every member of the join family converts its types by the one pattern,
// and is legal once its types are and it states no lifetime, its operands
// being only those it states.
template <JoinFamily... Groups>
void convertGroupTypes(const TypeConverter &converter, RewritePatternSet &patterns,
                       ConversionTarget &target) {
  patterns.add<ConvertGroupTypes<Groups>...>(converter, patterns.getContext());
  target.addDynamicallyLegalOp<Groups...>([&converter](Operation *op) {
    return op->getNumOperands() == 0 && converter.isLegal(op->getResultTypes()) &&
           llvm::all_of(op->getRegions(), [&](Region &region) {
             return converter.isLegal(region.getArgumentTypes());
           });
  });
}

// Every member of the join family becomes blocks by the one pattern, and
// none is left after.
template <JoinFamily... Groups>
void lowerGroups(RewritePatternSet &patterns, ConversionTarget &target) {
  patterns.add<LowerGroup<Groups>...>(patterns.getContext());
  target.addIllegalOp<Groups...>();
}

// idr.may_loop runs nothing, and goes where its loop becomes blocks: what
// it says reached LLVM before, in its function's row, which withholds
// `mustprogress`, and in its loop's jumps back, which carry no annotation
// that the loop makes progress.
struct EraseMayLoop : OpConversionPattern<MayLoopOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(MayLoopOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

// What `op` itself may do to keep a loop it stands in from ending: diverge,
// as it declares (idr.may_loop, a loop of code Idris did not prove to end,
// the one op of ours left that does); not return, as a call LLVM is not
// told returns may, the one form a callee's divergence has once calls are
// LLVM's, or an op whose effects may reach divergence; or nothing.
enum class Keeps : std::uint8_t { Nothing, Diverges, MayNotReturn };

Keeps keepsFromEnding(Operation *op) {
  if (auto call = dyn_cast<LLVM::CallOp>(op))
    return call.getWillReturn() ? Keeps::Nothing : Keeps::MayNotReturn;
  effects::EffectSet does = effects::own(op);
  if (does.on(effects::Kind::Write, ResourceId::Divergence))
    return Keeps::Diverges;
  return does.mayAct(effects::Kind::Write, ResourceId::Divergence) ? Keeps::MayNotReturn
                                                                   : Keeps::Nothing;
}

// Each idr.loop nothing in which may keep from ending is told it makes
// progress: every jump back into it carries upstream's annotation, which its
// lowering puts on the branch the jump becomes, as upstream's lowering of
// its own loops puts it on their latches. A loop that holds idr.may_loop,
// or holds a loop that does, or a call that may not return, is told
// nothing. One walk of the function: a loop is measured by the ops of its
// join regions, the ones that repeat, that may keep it from ending, counted
// between the first join region's entry and the last one's exit. A loop is
// told only in a function that holds one that may not end, whose row
// withholds `mustprogress` on that loop's account: of any other function,
// its row tells LLVM all there is to tell of its loops, so the code of a
// function Idris proved, and that took in no such loop, is what it was.
void tellProgress(Operation *fn, DictionaryAttr progresses) {
  unsigned keeping = 0;
  unsigned diverging = 0;
  SmallVector<unsigned, 4> atJoins;
  SmallVector<LoopOp> progressing;
  fn->walk([&](Operation *op, const WalkStage &stage) {
    if (op == fn)
      return;
    if (auto loop = dyn_cast<LoopOp>(op)) {
      if (stage.isBeforeRegion(1))
        atJoins.push_back(keeping);
      else if (stage.isAfterAllRegions() && atJoins.pop_back_val() == keeping)
        progressing.push_back(loop);
      return;
    }
    if (!stage.isBeforeAllRegions())
      return;
    switch (keepsFromEnding(op)) {
    case Keeps::Nothing:
      return;
    case Keeps::Diverges:
      ++diverging;
      ++keeping;
      return;
    case Keeps::MayNotReturn:
      ++keeping;
      return;
    }
  });
  if (diverging == 0)
    return;
  for (LoopOp loop : progressing)
    for (Region &region : loop.getJoinRegions())
      for (BlockArgument token : loop.getTokens(region))
        for (Operation *back : token.getUsers())
          back->setDiscardableAttrs(progresses);
}

} // namespace

void populateMatchPatterns(RewritePatternSet &patterns) {
  patterns.add<LowerMatch, LowerMatchLit>(patterns.getContext());
}

void populateJoinTypeConversions(const TypeConverter &converter, RewritePatternSet &patterns,
                                 ConversionTarget &target) {
  convertGroupTypes<
#define GET_JOIN_POINTS_FAMILY_LIST
#include "idr/IR/Generated/JoinPointsFamily.h.inc"
      >(converter, patterns, target);
  patterns.add<ConvertJumpTypes, ConvertGroupYieldTypes>(converter, patterns.getContext());
  target.addDynamicallyLegalOp<JumpOp>(
      [&converter](JumpOp op) { return converter.isLegal(op->getOperandTypes()); });
  target.addDynamicallyLegalOp<YieldOp>(
      [&converter](YieldOp op) { return converter.isLegal(op->getOperandTypes()); });
  // It has no type to convert, and phase 3 reads it before its loop is
  // blocks.
  target.addLegalOp<MayLoopOp>();
}

ControlFlowLowering::ControlFlowLowering(MLIRContext &context) : target(context) {
  RewritePatternSet set(&context);
  populateSCFToControlFlowConversionPatterns(set);
  lowerGroups<
#define GET_JOIN_POINTS_FAMILY_LIST
#include "idr/IR/Generated/JoinPointsFamily.h.inc"
      >(set, target);
  set.add<EraseMayLoop>(&context);
  patterns = FrozenRewritePatternSet(std::move(set));
  target.addIllegalOp<scf::ForallOp, scf::ForOp, scf::IfOp, scf::IndexSwitchOp, scf::LoopOp,
                      scf::ParallelOp, scf::WhileOp, scf::ExecuteRegionOp, MayLoopOp>();
  target.markUnknownOpDynamicallyLegal([](Operation *) { return true; });
  // Every loop that makes progress is told the same, upstream's annotation
  // of a latch, so it is made once, here, as the one dictionary a jump
  // carries, and no worker makes an attribute.
  auto annotation = LLVM::LoopAnnotationAttr::get(
      &context, {}, {}, {}, {}, {}, {}, {}, {}, {}, {},
      /*mustProgress=*/BoolAttr::get(&context, true), {}, {}, {}, {});
  progresses = DictionaryAttr::get(
      &context, {NamedAttribute(StringAttr::get(&context, LLVM::getLoopAnnotationAttrName()),
                                annotation)});
}

LogicalResult lowerControlFlow(Operation *root, const ControlFlowLowering &lowering) {
  tellProgress(root, lowering.progresses);
  return applyPartialConversion(root, lowering.target, lowering.patterns);
}

} // namespace idr::conversion
