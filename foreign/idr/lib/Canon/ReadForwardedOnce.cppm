// idr.canon:readforwardedonce: an scf.while whose scf.condition forwards
// one scf.if result at several positions reads it through the first.
export module idr.canon:readforwardedonce;

import idr.mlir;

using namespace mlir;

namespace {

// An scf.while whose scf.condition forwards one scf.if result at several
// positions: the after region reads it through the first of them only, and
// the arguments of the others are left unused. Upstream's WhileMoveIfDown
// gives the if's then value to the argument of the first position alone,
// so it is right only on a loop that reads no other; the benefit puts this
// pattern before it. PIN(while-move-if-down-duplicates) — see PINS.md
struct ReadForwardedOnce : OpRewritePattern<scf::WhileOp> {
  explicit ReadForwardedOnce(MLIRContext *context)
      : OpRewritePattern(context, /*benefit=*/2) {}

  LogicalResult matchAndRewrite(scf::WhileOp loop, PatternRewriter &rewriter) const override {
    llvm::SmallDenseMap<Value, BlockArgument> first;
    bool changed = false;
    for (auto [value, arg] : llvm::zip(loop.getConditionOp().getArgs(), loop.getAfterArguments())) {
      if (!value.getDefiningOp<scf::IfOp>())
        continue;
      auto [it, inserted] = first.try_emplace(value, arg);
      if (inserted || arg.use_empty())
        continue;
      rewriter.replaceAllUsesWith(arg, it->second);
      changed = true;
    }
    return success(changed);
  }
};

} // namespace

export namespace idr::canon {

// Adds the pattern that has a loop read a value its condition forwards
// twice through one argument.
void addReadForwardedOnce(RewritePatternSet &results) {
  results.add<ReadForwardedOnce>(results.getContext());
}

} // namespace idr::canon
