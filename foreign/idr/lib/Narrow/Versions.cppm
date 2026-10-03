// idr.narrow:versions: a loop whose natural only descends, versioned so
// that its copy proves the natural small.
export module idr.narrow:versions;

import idr.mlir;
import idr.dialect;
import idr.ranges;

import :facts;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

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

} // namespace idr::narrow
