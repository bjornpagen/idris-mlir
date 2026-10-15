// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-structure-loops: each loop of a function decided once, in one walk.
// The walk visits a loop after the loops inside it, so a nest is decided
// with its inner loops already made what they become, and a fold that a
// nest around it takes is left to that nest (planAt says which). What a
// rewrite makes is not visited again: one pass over each final body decides
// every loop, and nothing is left that the pass would still take.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Transforms/WalkPatternRewriteDriver.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTRUCTURELOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::structure {

bool structurable(Operation *loop) {
  auto counted = dyn_cast<scf::ForOp>(loop);
  return counted && planAt(counted).has_value();
}

namespace {

// What the walk made, counted where the pass reports it.
struct Counts {
  unsigned parallel = 0;
  unsigned reductions = 0;
};

struct Structure : OpRewritePattern<scf::ForOp> {
  Structure(MLIRContext *ctx, Counts &counts) : OpRewritePattern(ctx), counts(counts) {}

  LogicalResult matchAndRewrite(scf::ForOp loop, PatternRewriter &rewriter) const override {
    std::optional<Plan> plan = planAt(loop);
    if (!plan)
      return failure();
    Value made = build(rewriter, *plan);
    rewriter.replaceOp(loop, made);
    bool reduces = plan->form == Form::ReduceUnder || plan->form == Form::Reduce;
    ++(reduces ? counts.reductions : counts.parallel);
    return success();
  }

  Counts &counts;
};

struct StructureLoops : idr::impl::IdrStructureLoopsBase<StructureLoops> {
  void runOnOperation() override {
    Counts counts;
    RewritePatternSet patterns(&getContext());
    patterns.add<Structure>(&getContext(), counts);
    walkAndApplyPatterns(getOperation(), std::move(patterns));
    numParallel += counts.parallel;
    numReductions += counts.reductions;
  }
};

} // namespace

} // namespace idr::structure
