// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-identity: every call of a function that gives back one of its
// arguments becomes that argument, held at the quantity of the call's
// result. Once Idris's indices are erased, a function that only rebuilds
// its argument (Fin's weaken, a term's weakening to a larger scope)
// computes nothing; the Identities analysis finds them, once per round, on
// the module, and this pass rewrites each function's calls on its own.
//
// The function stays: this pass sees one function, and a closure may still
// name the callee. symbol-dce erases it once nothing does.
#include "idr/Transforms/Identity.h"

#include "idr/Analysis/Identities.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

namespace idr {
#define GEN_PASS_DEF_IDRIDENTITY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct GiveBack : OpRewritePattern<idr::CallOp> {
  GiveBack(MLIRContext *ctx, const idr::Identities &identities, unsigned &calls)
      : OpRewritePattern(ctx), identities(identities), calls(calls) {}

  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    std::optional<unsigned> given = identities.givesBack(call.getCalleeAttr().getAttr());
    if (!given)
      return failure();
    rewriter.replaceOp(call, idr::heldAs(rewriter, call.getLoc(), call.getArgs()[*given],
                                         call.getResult(0).getType()));
    ++calls;
    return success();
  }

  const idr::Identities &identities;
  unsigned &calls;
};

struct Identity : idr::impl::IdrIdentityBase<Identity> {
  void runOnOperation() override {
    auto identities = getCachedParentAnalysis<idr::Identities>();
    if (!identities) {
      getOperation().emitError("internal error: idr-identity runs without the Identities "
                               "analysis of its module");
      return signalPassFailure();
    }
    unsigned calls = 0;
    RewritePatternSet patterns(&getContext());
    patterns.add<GiveBack>(&getContext(), identities->get(), calls);
    walkAndApplyPatterns(getOperation(), std::move(patterns));
    numCalls += calls;
    if (calls == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace
