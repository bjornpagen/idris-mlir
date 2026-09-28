// The canonicalizations of the idr dialect (docs/cutover.md, section 6.2):
// the DRR patterns of Canonicalize.td, and in C++ those that DRR cannot
// state: apply of a known closure, the region patterns of the matches, and
// the removal of unused calls (OPT-CALL-1).

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {
#include "idr/IdrCanonicalize.inc"
} // namespace

//===----------------------------------------------------------------------===//
// Apply of a known closure (ELIM-G-1, ELIM-G-8)
//===----------------------------------------------------------------------===//

// `idr.apply` of `idr.closure @f(caps)` or of a constant `#idr.closure<@f,
// [caps]>` is `func.call @f(caps..., args...)`, as upstream's
// CallIndirectOp::canonicalize turns an indirect call of a constant into a
// direct call; `inline` does the rest.
LogicalResult ApplyOp::canonicalize(ApplyOp apply, PatternRewriter &rewriter) {
  FlatSymbolRefAttr callee;
  SmallVector<Value> operands;
  if (auto closure = apply.getCallee().getDefiningOp<ClosureOp>()) {
    callee = closure.getCalleeAttr();
    llvm::append_range(operands, closure.getCaptures());
  } else if (ClosureAttr constant; matchPattern(apply.getCallee(), m_Constant(&constant))) {
    callee = constant.getCallee();
    auto fn = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(apply, callee);
    if (!fn || constant.getCaptures().size() > fn.getNumArguments())
      return failure();
    auto captures = llvm::zip(constant.getCaptures(), fn.getArgumentTypes());
    Dialect *idr = apply->getDialect();
    if (!llvm::all_of(captures, [](auto capture) {
          auto [value, type] = capture;
          return ConstantOp::isBuildableWith(value, type) ||
                 arith::ConstantOp::isBuildableWith(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(
          idr->materializeConstant(rewriter, value, type, apply.getLoc())->getResult(0));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.replaceOpWithNewOp<func::CallOp>(apply, callee, apply.getResultTypes(), operands);
  return success();
}

//===----------------------------------------------------------------------===//
// Matches (ELIM-G-2, A3, A4)
//===----------------------------------------------------------------------===//

namespace {

// A match like `op`, with `types` as results, `cases` and the regions
// `regions` (moved), the default last if there is one.
template <typename Match>
Match rebuildMatch(PatternRewriter &rewriter, Match op, TypeRange types,
                   ArrayRef<Attribute> cases, ArrayRef<Region *> regions) {
  auto fresh = Match::create(rewriter, op.getLoc(), types, op.getScrutinee(),
                             rewriter.getArrayAttr(cases), regions.size());
  fresh->setDiscardableAttrs(op->getDiscardableAttrDictionary());
  for (auto [to, from] : llvm::zip(fresh.getRegions(), regions))
    rewriter.inlineRegionBefore(*from, to, to.end());
  return fresh;
}

// Whether two regions do the same thing without reading their arguments.
bool sameBody(Region &a, Region &b) {
  Block &x = a.front(), &y = b.front();
  auto unused = [](Block &block) {
    return llvm::all_of(block.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
  };
  if (!unused(x) || !unused(y) || x.getOperations().size() != y.getOperations().size())
    return false;
  DenseMap<Value, Value> same;
  return llvm::all_of_zip(x, y, [&](Operation &l, Operation &r) {
    return OperationEquivalence::isEquivalentTo(
        &l, &r,
        [&](Value lv, Value rv) { return success(lv == rv || same.lookup(lv) == rv); },
        [&](Value lv, Value rv) { same[lv] = rv; }, OperationEquivalence::IgnoreLocations);
  });
}

// Identical regions merge: a case that does what the default does is left to
// the default, and without a default, cases that do the same become it.
template <typename Match>
struct MergeIdenticalRegions : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    unsigned count = static_cast<unsigned>(op.getCases().size());
    Region *fallback = op.getDefaultRegion();
    if (!fallback)
      for (unsigned i = 0; i < count && !fallback; ++i)
        for (unsigned j = i + 1; j < count && !fallback; ++j)
          if (sameBody(op.getCaseRegion(i), op.getCaseRegion(j)))
            fallback = &op.getCaseRegion(i);
    if (!fallback)
      return failure();
    SmallVector<Attribute> cases;
    SmallVector<Region *> regions;
    for (unsigned i = 0; i < count; ++i)
      if (&op.getCaseRegion(i) != fallback && !sameBody(op.getCaseRegion(i), *fallback)) {
        cases.push_back(op.getCases()[i]);
        regions.push_back(&op.getCaseRegion(i));
      }
    if (regions.size() + 1 == op.getRegions().size() && fallback == op.getDefaultRegion())
      return failure();
    // The new default takes no arguments; the old region's are unused.
    rewriter.modifyOpInPlace(op, [&] {
      fallback->front().eraseArguments(0, fallback->getNumArguments());
    });
    regions.push_back(fallback);
    rewriter.replaceOp(op, rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

// Whether `consumer` folds or canonicalizes when its operand is `value`: a
// constant, a constructor, a closure, or, for output and the first
// character, a string builder (A2, A4).
bool feeds(Value value, Operation *consumer) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<ConOp, ClosureOp>(def))
    return true;
  return isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def) &&
         isa<PutStrOp, StrHeadOp>(consumer);
}

// A3, case-of-case: the single consumer of a result of a match moves into
// every region that yields, when in at least one of them it then meets a
// value it folds or canonicalizes against. It moves past no op with effects,
// and still runs exactly once on every path (OPT-SAFE-1).
template <typename Match>
struct SinkConsumer : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    for (OpResult result : op->getResults())
      if (Operation *consumer = sinkable(op, result))
        return sink(op, consumer, rewriter);
    return failure();
  }

private:
  static Operation *sinkable(Match op, OpResult result) {
    if (!result.hasOneUse())
      return nullptr;
    Operation *consumer = *result.getUsers().begin();
    Block *block = op->getBlock();
    if (consumer->getBlock() != block || consumer->hasTrait<OpTrait::IsTerminator>() ||
        consumer->getNumRegions() != 0)
      return nullptr;
    // Its other operands are the match's results or exist before the match.
    for (Value operand : consumer->getOperands()) {
      Operation *def = operand.getDefiningOp();
      if (def && def != op && def->getBlock() == block && op->isBeforeInBlock(def))
        return nullptr;
    }
    for (Operation *between = op->getNextNode(); between != consumer;
         between = between->getNextNode())
      if (!isMemoryEffectFree(between))
        return nullptr;
    bool feedsSome = llvm::any_of(op.getRegions(), [&](Region &region) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      return yield && feeds(yield.getOperand(result.getResultNumber()), consumer);
    });
    return feedsSome ? consumer : nullptr;
  }

  static LogicalResult sink(Match op, Operation *consumer, PatternRewriter &rewriter) {
    unsigned kept = op->getNumResults();
    SmallVector<Type> types(op->getResultTypes());
    llvm::append_range(types, consumer->getResultTypes());
    SmallVector<Region *> regions = llvm::map_to_vector(
        op.getRegions(), [](Region &region) { return &region; });
    rewriter.setInsertionPoint(op);
    Match fresh = rebuildMatch(rewriter, op, types, llvm::to_vector(op.getCases()), regions);
    for (Region &region : fresh.getRegions()) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      IRMapping mapping;
      mapping.map(op->getResults(), yield.getOperands());
      rewriter.setInsertionPoint(yield);
      Operation *copy = rewriter.clone(*consumer, mapping);
      rewriter.modifyOpInPlace(yield, [&] {
        yield->insertOperands(yield->getNumOperands(), copy->getResults());
      });
    }
    rewriter.replaceOp(consumer, fresh->getResults().drop_front(kept));
    rewriter.replaceOp(op, fresh->getResults().take_front(kept));
    return success();
  }
};

// A4: a string that cannot be empty never takes the case `""`.
struct DropEmptyStringCase : OpRewritePattern<MatchLitOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(MatchLitOp op, PatternRewriter &rewriter) const final {
    auto empty = rewriter.getStringAttr("");
    const auto *it = llvm::find(op.getCases(), empty);
    if (it == op.getCases().end() || !knownNonEmpty(op.getScrutinee()))
      return failure();
    auto dropped = static_cast<unsigned>(it - op.getCases().begin());
    SmallVector<Attribute> cases;
    SmallVector<Region *> regions;
    for (auto [index, region] : llvm::enumerate(op.getRegions()))
      if (index != dropped) {
        if (index < op.getCases().size())
          cases.push_back(op.getCases()[index]);
        regions.push_back(&region);
      }
    rewriter.replaceOp(op, rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

// A case region's arguments are its constructor's fields.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOp>(arg.getOwner()->getParentOp());
  auto ctor = cast<FlatSymbolRefAttr>(
      match.getCases()[arg.getOwner()->getParent()->getRegionNumber()]);
  return FieldOp::create(builder, loc, arg.getType(), match.getScrutinee(), ctor,
                         builder.getI64IntegerAttr(arg.getArgNumber()));
}

// Upstream's region patterns, as scf.index_switch uses them: results no
// region needs drop, and a match whose taken region is known (a constant or
// an idr.con scrutinee, or one region left) is replaced by that region, whose
// arguments become idr.field reads that fold.
template <typename Match>
void populateMatchPatterns(RewritePatternSet &results, MLIRContext *context,
                           NonSuccessorInputReplacementBuilderFn replacement) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results,
                                                          Match::getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, Match::getOperationName(),
                                                 replacement);
  results.add<MergeIdenticalRegions<Match>, SinkConsumer<Match>>(context);
}

} // namespace

void MatchOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  populateMatchPatterns<MatchOp>(results, context, readField);
}

void MatchLitOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                             MLIRContext *context) {
  populateMatchPatterns<MatchLitOp>(results, context,
                                    mlir::detail::defaultReplBuilderFn);
  results.add<DropEmptyStringCase>(context);
}

//===----------------------------------------------------------------------===//
// Strings (A2, A4)
//===----------------------------------------------------------------------===//

void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble>(context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble>(context);
}

//===----------------------------------------------------------------------===//
// Unused calls (OPT-CALL-1, A20)
//===----------------------------------------------------------------------===//

namespace {

// Whether a value of `type` may hold a closure, in a field or a capture.
bool mayHoldClosure(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  if (isa<FnType>(type))
    return true;
  DataOp data = lookupData(from, type);
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return mayHoldClosure(from, field, seen); });
  });
}

bool removable(func::FuncOp fn) { return fn && isPure(fn) && isTotal(fn) && !mayCrash(fn); }

// A call passes on no effect through `value`: it holds no closure, or only
// closures of functions whose calls could be removed too.
bool passesNoEffect(Operation *call, Value value) {
  llvm::SmallDenseSet<Type> seen;
  if (!mayHoldClosure(call, value.getType(), seen))
    return true;
  Attribute constant;
  if (!matchPattern(value, m_Constant(&constant)))
    return false;
  return !constant
              .walk([&](ClosureAttr closure) {
                return removable(SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(
                           call, closure.getCallee()))
                           ? WalkResult::advance()
                           : WalkResult::interrupt();
              })
              .wasInterrupted();
}

// A call whose results are unused goes when its callee is pure, total and
// cannot crash: it could only run, and SEM-EVAL-4 keeps a crash even when
// its result is unused.
struct RemoveUnusedCall : OpRewritePattern<func::CallOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(func::CallOp call, PatternRewriter &rewriter) const final {
    if (!call->use_empty() ||
        !removable(SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr())) ||
        !llvm::all_of(call.getOperands(),
                      [&](Value operand) { return passesNoEffect(call, operand); }))
      return failure();
    rewriter.eraseOp(call);
    return success();
  }
};

} // namespace

void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  results.add<RemoveUnusedCall>(getContext());
}
