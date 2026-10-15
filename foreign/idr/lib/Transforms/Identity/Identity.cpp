// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-identity: every call of a function that gives back one of its
// arguments becomes that argument, held at the quantity of the call's
// result. Once Idris's indices are erased, a function that only rebuilds
// its argument (Fin's weaken, a term's weakening to a larger scope)
// computes nothing. idr-optimize solves what the members of each component
// of its ready set give back when it takes the component up, its callees'
// already final, and keeps it on each node's summary; this pass, a step of
// its inner pipeline, rewrites one function's calls on what is solved.
//
// The function stays: this pass sees one function, and another may still
// call the callee. idr-optimize erases it once nothing names it.
#include "idr/Transforms/Identity.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

namespace idr {
#define GEN_PASS_DEF_IDRIDENTITY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct GiveBack : OpRewritePattern<idr::CallOp> {
  GiveBack(MLIRContext *ctx, const idr::optimize::ReadySet &set, const idr::optimize::Node &reader,
           unsigned &calls)
      : OpRewritePattern(ctx), set(set), reader(reader), calls(calls) {}

  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    std::optional<unsigned> given = set.givesBack(reader, call.getCalleeAttr().getAttr());
    if (!given)
      return failure();
    rewriter.replaceOp(call, idr::heldAs(rewriter, call.getLoc(), call.getArgs()[*given],
                                         call.getResult(0).getType()));
    ++calls;
    return success();
  }

  const idr::optimize::ReadySet &set;
  const idr::optimize::Node &reader;
  unsigned &calls;
};

struct Identity : idr::impl::IdrIdentityBase<Identity> {
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto set = getCachedParentAnalysis<idr::optimize::ReadySet>();
    const idr::optimize::Node *reader = set ? set->get().nodeOf(fn.getSymNameAttr()) : nullptr;
    if (!reader) {
      fn.emitError("internal error: idr-identity runs inside idr-optimize, on a function of its "
                   "ready set");
      return signalPassFailure();
    }
    unsigned calls = 0;
    RewritePatternSet patterns(&getContext());
    patterns.add<GiveBack>(&getContext(), set->get(), *reader, calls);
    walkAndApplyPatterns(fn, std::move(patterns));
    numCalls += calls;
    if (calls == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace
