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
#include "idr/Support/Actions.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include <cassert>

namespace idr {
#define GEN_PASS_DEF_IDRIDENTITY
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// idr-identity makes one call the argument it gives back; the unit is the
// call.
struct IdentityCallAction : idr::support::TaggedAction<IdentityCallAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-identity-call";
};

struct GiveBack : OpRewritePattern<idr::CallOp> {
  GiveBack(MLIRContext *ctx, const idr::optimize::ReadySet &set, const idr::optimize::Node &reader,
           unsigned &calls)
      : OpRewritePattern(ctx), set(set), reader(reader), calls(calls) {}

  LogicalResult matchAndRewrite(idr::CallOp call, PatternRewriter &rewriter) const override {
    std::optional<unsigned> given = set.givesBack(reader, call.getCalleeAttr().getAttr());
    if (!given)
      return failure();
    if (!idr::support::perform<IdentityCallAction>(call, [&] {
          rewriter.replaceOp(call, idr::heldAs(rewriter, call.getLoc(), call.getArgs()[*given],
                                               call.getResult(0).getType()));
        }))
      return failure();
    ++calls;
    return success();
  }

  const idr::optimize::ReadySet &set;
  const idr::optimize::Node &reader;
  unsigned &calls;
};

struct Identity : idr::impl::IdrIdentityBase<Identity> {
  Identity(const idr::optimize::ReadySet &set, Pass::Statistic &numCalls)
      : set(set), numCalls(numCalls) {}

  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    // The scheduler runs the pipeline on the functions of its ready set.
    const idr::optimize::Node *reader = set.nodeOf(fn.getSymNameAttr());
    assert(reader && "the inner pipeline runs on a function of the ready set");
    unsigned calls = 0;
    RewritePatternSet patterns(&getContext());
    patterns.add<GiveBack>(&getContext(), set, *reader, calls);
    walkAndApplyPatterns(fn, std::move(patterns));
    numCalls += calls;
    if (calls == 0)
      markAllAnalysesPreserved();
  }

  const idr::optimize::ReadySet &set;
  Pass::Statistic &numCalls;
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createIdentity(const ReadySet &set, Pass::Statistic &calls) {
  return std::make_unique<Identity>(set, calls);
}
