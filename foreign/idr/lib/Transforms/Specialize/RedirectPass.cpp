// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-redirect: a call whose key names a clone the module already holds
// calls that clone, function by function. It is the redirect half of
// idr-specialize: it makes no clone, and a key the table lacks waits for
// idr-specialize.
//
// The tables are the module's, left cached by idr-round-facts just before
// the nest, and are read here by name: the callee's name comes from the call, its binding
// times and clone record from the tables, and the clone's name, type and
// effects from its record. So no function looks at another, and the
// functions are redirected in parallel.
//
// Raising is tried first, as idr-specialize does: a raised call may then
// specialize. A redirect erases the consumer and the shapes that fed the
// call, which are not the call, so the patterns run under the greedy
// driver; with folding, constant CSE and region simplification off, the
// pass only redirects.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Analysis/Holds.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRREDIRECT
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;
using namespace idr::specialize;

namespace {

// A call whose result only an apply consumes, when the table holds the
// clone raised for its callee and that consumer.
struct RaisePattern : OpRewritePattern<idr::CallOp> {
  RaisePattern(MLIRContext *ctx, const idr::CloneTable &clones, const idr::Holds &holds,
               unsigned &redirected)
      : OpRewritePattern(ctx, /*benefit=*/2), clones(clones), holds(holds),
        redirected(redirected) {}

  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    std::optional<Consumer> consumer = consumerOf(call, holds);
    if (!consumer)
      return failure();
    const idr::Clone *clone = clones.lookup(raiseKey(call, *consumer));
    if (!clone)
      return failure();
    bool done = false;
    idr::support::perform<idr::RaiseAction>(call, [&] {
      SmallVector<Value> operands(call.getArgs());
      llvm::append_range(operands, consumer->apply.getArgs());
      done = redirect(rewriter, call, *clone, operands, consumer).has_value();
    });
    if (!done)
      return failure();
    ++redirected;
    return success();
  }

  const idr::CloneTable &clones;
  const idr::Holds &holds;
  unsigned &redirected;
};

// A call whose static arguments compose the key of a specialization the
// table holds.
struct SpecializePattern : OpRewritePattern<idr::CallOp> {
  SpecializePattern(MLIRContext *ctx, const idr::CloneTable &clones,
                    const idr::BindingTimes &times, unsigned &redirected)
      : OpRewritePattern(ctx, /*benefit=*/1), clones(clones), times(times),
        redirected(redirected) {}

  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    std::optional<Composed> composed = composeKey(call, clones, times);
    if (!composed)
      return failure();
    const idr::Clone *clone = clones.lookup(composed->key);
    if (!clone)
      return failure();
    bool done = false;
    idr::support::perform<idr::SpecializeCloneAction>(call, [&] {
      done = redirect(rewriter, call, *clone, composed->values, std::nullopt).has_value();
    });
    if (!done)
      return failure();
    ++redirected;
    return success();
  }

  const idr::CloneTable &clones;
  const idr::BindingTimes &times;
  unsigned &redirected;
};

struct Redirect : idr::impl::IdrRedirectBase<Redirect> {
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto clones = getCachedParentAnalysis<idr::CloneTable>();
    auto times = getCachedParentAnalysis<idr::BindingTimes>();
    auto holds = getCachedParentAnalysis<idr::Holds>();
    auto absent = [&](llvm::StringRef name) {
      fn.emitError() << "internal error: idr-redirect needs the " << name
                     << " analysis of its module";
      signalPassFailure();
    };
    if (!clones)
      return absent("CloneTable");
    if (!times)
      return absent("BindingTimes");
    if (!holds)
      return absent("Holds");

    unsigned redirected = 0;
    MLIRContext *ctx = &getContext();
    RewritePatternSet set(ctx);
    set.add<RaisePattern>(ctx, clones->get(), holds->get(), redirected);
    set.add<SpecializePattern>(ctx, clones->get(), times->get(), redirected);
    FrozenRewritePatternSet patterns(std::move(set));
    GreedyRewriteConfig config;
    config.enableFolding(false).enableConstantCSE(false).setRegionSimplificationLevel(
        GreedySimplifyRegionLevel::Disabled);
    bool changed = false;
    // Whether the driver converged is not the question: every redirect it
    // made stands.
    (void)applyPatternsGreedily(fn, patterns, config, &changed);
    numRedirected += redirected;
    if (!changed)
      markAllAnalysesPreserved();
  }
};

} // namespace
