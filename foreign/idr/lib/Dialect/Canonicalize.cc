// The canonicalizations of the idr dialect:
// the DRR patterns of Canonicalize.td, and in C++ those that DRR cannot
// state: apply of a known closure, the region patterns of the matches, and
// the removal of unused calls.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;
using namespace idr;

namespace {
#include "idr/IdrCanonicalize.inc"
} // namespace

//===----------------------------------------------------------------------===//
// Apply of a known closure
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
    Dialect *dialect = apply->getDialect();
    if (!llvm::all_of(captures, [](auto capture) {
          auto [value, type] = capture;
          return ConstantOp::isBuildableWith(value, type) ||
                 arith::ConstantOp::isBuildableWith(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(
          dialect->materializeConstant(rewriter, value, type, apply.getLoc())->getResult(0));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.replaceOpWithNewOp<func::CallOp>(apply, callee, apply.getResultTypes(), operands);
  return success();
}

//===----------------------------------------------------------------------===//
// Matches
//===----------------------------------------------------------------------===//

namespace {

// A match like `op`, with `types` as results, `cases` and the regions
// `regions` (moved), the default last if there is one.
template <typename Match>
Match rebuildMatch(PatternRewriter &rewriter, Match op, TypeRange types,
                   ArrayRef<Attribute> cases, ArrayRef<Region *> regions) {
  auto fresh = Match::create(rewriter, op.getLoc(), types, op.getScrutinee(),
                             rewriter.getArrayAttr(cases),
                             static_cast<unsigned>(regions.size()));
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
// character, a string builder.
bool feeds(Value value, Operation *consumer) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<ConOp, ClosureOp>(def))
    return true;
  return isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def) &&
         isa<PutStrOp, StrHeadOp>(consumer);
}

// Whether a call only computes: its callee is pure, as idr-effects found (a
// call declares no effects of its own, so MLIR takes it to have any), and,
// unless `partial`, total and unable to crash, so that whether it runs at all
// cannot be observed either.
bool computes(func::CallOp call, bool partial) {
  auto callee = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
  if (!callee)
    return false;
  auto effect = callee->getAttrOfType<StringAttr>("idr.effect");
  return effect && effect.getValue() == "pure" &&
         (partial || (callee->hasAttr("idr.total") && !callee->hasAttr("idr.may_crash")));
}

// Whether moving `op` cannot be observed: nothing in it has an effect but
// allocation (a string or a big it builds, which nothing can see), and every
// call in it only computes. With `partial`, a call may also fail to return
// or crash: then `op` may move, but must still run on every path it ran on.
bool movable(Operation *op, bool partial = false) {
  WalkResult result = op->walk([&](Operation *inner) {
    if (auto call = dyn_cast<func::CallOp>(inner))
      return computes(call, partial) ? WalkResult::advance() : WalkResult::interrupt();
    if (inner->hasTrait<OpTrait::HasRecursiveMemoryEffects>())
      return WalkResult::advance();
    auto iface = dyn_cast<MemoryEffectOpInterface>(inner);
    if (!iface)
      return WalkResult::interrupt();
    SmallVector<MemoryEffects::EffectInstance> effects;
    iface.getEffects(effects);
    return llvm::all_of(effects,
                        [](const MemoryEffects::EffectInstance &effect) {
                          return isa<MemoryEffects::Allocate>(effect.getEffect());
                        })
               ? WalkResult::advance()
               : WalkResult::interrupt();
  });
  return !result.wasInterrupted();
}

// Case-of-case: the single consumer of a result of a match,
// another match included, moves into every region that yields, when in at
// least one of them it then meets a value it folds or canonicalizes against.
// The consumer moves past no op with effects (an allocation aside), and still
// runs exactly once on every path. When it cannot move up to the
// match, a match whose only effects are allocations moves down to it
// instead, past the ops between them: a value computed without effects may
// be computed later.
template <typename Match>
struct SinkConsumer : OpRewritePattern<Match> {
  explicit SinkConsumer(MLIRContext *context) : OpRewritePattern<Match>(context) {
    this->setDebugName("idr-sink-consumer");
  }
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    for (OpResult result : op->getResults()) {
      Operation *consumer = candidate(op, result);
      if (!consumer)
        continue;
      if (canRaise(op, consumer))
        return sink(op, consumer, rewriter);
      if (canLower(op, consumer)) {
        rewriter.moveOpBefore(op, consumer);
        return sink(op, consumer, rewriter);
      }
    }
    return failure();
  }

private:
  // The single consumer of `result`, in the match's block, when it would
  // meet in some region a value it folds or canonicalizes against.
  static Operation *candidate(Match op, OpResult result) {
    if (!result.hasOneUse())
      return nullptr;
    Operation *consumer = *result.getUsers().begin();
    if (consumer->getBlock() != op->getBlock() || consumer->hasTrait<OpTrait::IsTerminator>())
      return nullptr;
    bool feedsSome = llvm::any_of(op.getRegions(), [&](Region &region) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      return yield && feeds(yield.getOperand(result.getResultNumber()), consumer);
    });
    return feedsSome ? consumer : nullptr;
  }

  // Whether `consumer` can move up to the match: its other operands, and the
  // values its regions use from outside, are the match's results or exist
  // before the match, and no op between them has effects but allocation.
  static bool canRaise(Match op, Operation *consumer) {
    Block *block = op->getBlock();
    auto before = [&](Value value) {
      Operation *def = value.getDefiningOp();
      return !def || def == op || def->getBlock() != block || def->isBeforeInBlock(op);
    };
    if (!llvm::all_of(consumer->getOperands(), before))
      return false;
    bool captured = true;
    visitUsedValuesDefinedAbove(consumer->getRegions(), [&](OpOperand *use) {
      captured &= before(use->get());
    });
    if (!captured)
      return false;
    for (Operation *between = op->getNextNode(); between != consumer;
         between = between->getNextNode())
      if (!movable(between))
        return false;
    return true;
  }

  // Whether the match can move down to `consumer`: it has no effects but
  // allocation, and nothing between them uses its results. Its operands and the values its
  // regions use exist before it, so they exist before the consumer too.
  static bool canLower(Match op, Operation *consumer) {
    if (!movable(op))
      return false;
    return llvm::all_of(op->getUsers(), [&](Operation *user) {
      Operation *at = op->getBlock()->findAncestorOpInBlock(*user);
      return at && (at == consumer || consumer->isBeforeInBlock(at));
    });
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

// A value computed in the match's block, free of effects (an
// allocation aside), and used only inside the match's regions moves into each
// region that uses it, when there it meets a consumer that folds against it:
// output of a string it builds, or a consumer a match of its moves into
// (case-of-case). Only one region runs, so the value is still computed at most
// once. A value that may not return or may crash moves only when every region
// uses it and nothing with an effect lies between it and the match: every
// path still computes it, before anything it could hide. The copies are
// bounded: each region past the first may receive at
// most kSinkBudget ops, so a large match is not copied into every case of
// another. A constant stays where it is: the folder hoists constants back,
// and each would undo the other.
constexpr int64_t kSinkBudget = 64;
template <typename Match>
struct SinkIntoRegions : OpRewritePattern<Match> {
  explicit SinkIntoRegions(MLIRContext *context) : OpRewritePattern<Match>(context) {
    this->setDebugName("idr-sink-into-regions");
  }
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    // The candidates are the ops before the match in its block. Visiting the
    // values its regions use instead would walk all of its nested regions
    // each time the match is revisited, and the rewrite driver revisits a
    // match whenever anything inside it changes: in a function whose matches
    // nest dozens deep, as case-of-case makes them, that dominated
    // compilation.
    Operation *value = nullptr;
    for (Operation *def = op->getPrevNode(); def && !value; def = def->getPrevNode())
      if (sinkable(def, op))
        value = def;
    if (!value)
      return failure();
    for (Region &region : op->getRegions()) {
      auto inside = [&](OpOperand &use) { return region.isAncestor(use.getOwner()->getParentRegion()); };
      if (llvm::none_of(value->getUses(), inside))
        continue;
      rewriter.setInsertionPointToStart(&region.front());
      Operation *copy = rewriter.clone(*value);
      rewriter.replaceUsesWithIf(value->getResults(), copy->getResults(), inside);
    }
    rewriter.eraseOp(value);
    return success();
  }

private:
  static bool sinkable(Operation *value, Operation *match) {
    if (value->getNumResults() == 0 || value->use_empty() ||
        value->hasTrait<OpTrait::ConstantLike>())
      return false;
    if (!llvm::all_of(value->getUsers(), [&](Operation *user) {
          return user != match && match->isAncestor(user);
        }))
      return false;
    if (!movable(value)) {
      bool everyRegion = llvm::all_of(match->getRegions(), [&](Region &region) {
        return llvm::any_of(value->getUsers(), [&](Operation *user) {
          return region.isAncestor(user->getParentRegion());
        });
      });
      bool nothingBetween = true;
      for (Operation *between = value->getNextNode(); between != match;
           between = between->getNextNode())
        nothingBetween &= movable(between);
      if (!everyRegion || !nothingBetween || !movable(value, /*partial=*/true))
        return false;
    }
    if (!llvm::any_of(value->getResults(), [](Value result) {
          return llvm::any_of(result.getUsers(), [&](Operation *user) { return meets(result, user); });
        }))
      return false;
    int64_t regions = llvm::count_if(match->getRegions(), [&](Region &region) {
      return llvm::any_of(value->getUsers(), [&](Operation *user) {
        return region.isAncestor(user->getParentRegion());
      });
    });
    int64_t size = 0;
    value->walk([&](Operation *) { ++size; });
    return (regions - 1) * size <= kSinkBudget;
  }

  // Whether `user` folds or canonicalizes against `value` once they meet:
  // what feeds() says for a value an op builds, and for a match's result,
  // a consumer that case-of-case would move into the match.
  static bool meets(Value value, Operation *user) {
    if (feeds(value, user))
      return true;
    auto result = dyn_cast<OpResult>(value);
    if (!result || !isa<MatchOp, MatchLitOp>(result.getOwner()))
      return false;
    return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      return yield && feeds(yield.getOperand(result.getResultNumber()), user);
    });
  }
};

// A string that cannot be empty never takes the
// case `""`.
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
    for (unsigned index = 0, count = op->getNumRegions(); index < count; ++index)
      if (index != dropped) {
        if (index < op.getCases().size())
          cases.push_back(op.getCases()[index]);
        regions.push_back(&op->getRegion(index));
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
  results.add<MergeIdenticalRegions<Match>, SinkConsumer<Match>, SinkIntoRegions<Match>>(context);
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
// Strings
//===----------------------------------------------------------------------===//

void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble>(context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble>(context);
}

//===----------------------------------------------------------------------===//
// Unused calls
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
// cannot crash: it could only run, and a crash stays even when its result
// is unused.
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
