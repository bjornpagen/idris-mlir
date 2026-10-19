// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize: the ready set over the program. The functions nothing names
// any more are upstream's symbol-dce's, which the pipeline runs after it.
//
// A pass on the program, as upstream's inliner is on its module: inlining
// reads a sibling of the function it rewrites, which a nested pass may
// not, and the ready set is what makes the read safe, since a callee is
// read only once it is final and nothing writes it again. Every other
// rewrite is a pass of the inner pipeline, run with runPipeline so that
// the verifier and the manager's instrumentation run on each function as
// they would under a nest. What those passes read of the run (the ready
// set, which holds every summary, and the node table) each is given when it
// is made, so none runs outside a run of this pass.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Inline.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Identity.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/OptimizeScheduler.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"

#include <algorithm>

namespace idr {
#define GEN_PASS_DEF_IDROPTIMIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

// A pass statistic must have the layout the MLIR library gives it, which
// holds the count: the pinned LLVM is built with LLVM_FORCE_ENABLE_STATS,
// so its llvm-config.h says statistics count in our Release build too, and
// idr-optimize's counts of what it inlined, capped and made are read off
// them.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

void idr::optimize::buildInnerPipeline(OpPassManager &pm, const InnerRun &run) {
  const InnerCounts &counts = run.counts;
  // Before canonicalization, on what the component solved when it was
  // taken up: a call of a function that only rebuilds its argument is gone
  // before anything weighs it.
  pm.addPass(createIdentity(run.set, counts.identityCalls));
  // Upstream's, which read a call's own effects: a call of a callee that
  // only computes goes when nothing reads it, and merges with an equal one
  // that dominates it. Region simplification would re-simplify the region
  // tree after every pattern iteration, on every run of this pipeline on a
  // body, at a cost that grows with the bodies inlining builds, for what
  // cse and remove-dead-values already remove. The worklist is seeded top
  // down, as upstream's canonicalizer seeds it.
  pm.addPass(createCanonicalizerPass(
      GreedyRewriteConfig().setUseTopDownTraversal().setRegionSimplificationLevel(
          GreedySimplifyRegionLevel::Disabled)));
  pm.addPass(createCSEPass());
  // On what canonicalization and CSE left: a call whose arguments are
  // known constructors asks for its specialization and calls it.
  pm.addPass(createRedirect(run.nodes, counts.redirected));
  // Last, so that the body a caller's summary is read from is the one this
  // solve left.
  pm.addPass(createConstants(run.set, counts.constants));
}

namespace {

// The ready set and the node table are this run's own, and so is the inner
// pipeline every worker copies: each step is made with what it reads of
// them and the statistics of this pass it counts into. The dialects the
// steps make are this pass's to load, which it declares.
struct Optimize : idr::impl::IdrOptimizeBase<Optimize> {
  void runOnProgram(idr::ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    idr::optimize::ReadySet set(program, getAnalysis<idr::CallCycles>());
    // The ready set is the node table's schedule.
    const idr::specialize::Nodes nodes(set);
    const idr::optimize::InnerCounts counts{numIdentityCalls, numRedirected, numConstants, numCSE,
                                            numDCE};
    const idr::optimize::InnerRun inner{set, nodes, counts};
    // Every function's analysis manager exists before any task, so a
    // pipeline's own nesting finds it instead of inserting it.
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      (void)getAnalysisManager().nest(fn);

    idr::optimize::Scheduler scheduler(
        {program, set, symbols, nodes, inner, getAnalysisManager()},
        [this](OpPassManager &pm, Operation *op) { return runPipeline(pm, op); });
    LogicalResult ran = scheduler.run();
    scheduler.addInnerStatistics();
    numInlined += scheduler.inlined();
    numCapped += scheduler.capped();
    numNodes += scheduler.made();
    if (failed(ran))
      return signalPassFailure();

    // Every function is final once the run succeeded.
    int64_t largest = 0;
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      largest = std::max(largest, idr::inlineSize(fn));
    if (remark::detail::InFlightRemark finished = remark::analysis(
            program.getLoc(), remark::RemarkOpts::name("finished").category("idr-optimize")))
      finished << remark::metric("nodes", set.nodeCount()) << remark::metric("made", scheduler.made())
               << remark::metric("largest", largest) << remark::metric("capped", scheduler.capped());
    // No type changed; every other analysis is stale.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
