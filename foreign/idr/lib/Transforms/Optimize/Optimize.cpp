// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize: the ready set over the program, then the functions nothing
// names any more erased, by upstream's symbol-dce.
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
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Identity.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"

#include <algorithm>
#include <cassert>
#include <optional>

namespace idr {
#define GEN_PASS_DEF_IDROPTIMIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

// A pass statistic must have the layout the MLIR library gives it, which
// holds the count: the pinned LLVM is built with LLVM_FORCE_ENABLE_STATS,
// so its llvm-config.h says statistics count in our Release build too, and
// idr-optimize's counts of what it inlined, capped, erased and made are
// read off them.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

void idr::optimize::buildInnerPipeline(OpPassManager &pm, const InnerRun &run) {
  const InnerCounts &counts = run.counts;
  // Before canonicalization, on what the component solved when it was
  // taken up: a call of a function that only rebuilds its argument is gone
  // before anything weighs it.
  pm.addPass(createIdentity(run.set, counts.identityCalls));
  pm.addPass(idr::createCanonicalizerPass(&run.effects));
  // A call is opaque to canonicalize and CSE, which cannot read its callee;
  // the summaries can, so the calls of pure callees go or merge here, and
  // CSE then merges what their operands' merging made equal.
  pm.addPass(createPureCalls(run.set, counts.pureErased, counts.pureMerged));
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
  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    // What a call does is its callee's, found through the program's table,
    // which the run keeps current.
    const idr::CalleeEffects effects{symbols};
    idr::optimize::ReadySet set(program);
    // The ready set is the node table's schedule and its binding times.
    const idr::specialize::Nodes nodes(set, set, effects);
    const idr::optimize::InnerCounts counts{numIdentityCalls, numPureErased, numPureMerged,
                                            numRedirected, numConstants};
    const idr::optimize::InnerRun inner{set, nodes, effects, counts};
    // Every function's analysis manager exists before any task, so a
    // pipeline's own nesting finds it instead of inserting it.
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      (void)getAnalysisManager().nest(fn);

    idr::optimize::Scheduler scheduler(
        {program, set, symbols, nodes, inner, getAnalysisManager()},
        [this](OpPassManager &pm, Operation *op) { return runPipeline(pm, op); });
    LogicalResult ran = scheduler.run();
    numInlined += scheduler.inlined();
    numCapped += scheduler.capped();
    numNodes += scheduler.made();
    if (failed(ran))
      return signalPassFailure();

    int64_t largest = 0;
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      if (const idr::optimize::Summary *summary = set.summaryOf(fn.getSymNameAttr()))
        largest = std::max(largest, summary->facts.size);
    // Every function no symbol use reaches from the root goes, by
    // upstream's symbol-dce: a function's visibility is read off the
    // program's root, public for it and private for every other.
    auto functions = [&] { return llvm::range_size(program.getOps<idr::FuncOp>()); };
    size_t before = functions();
    OpPassManager dead(idr::ProgramOp::getOperationName());
    dead.addPass(createSymbolDCEPass());
    if (failed(runPipeline(dead, program)))
      return signalPassFailure();
    numErased += before - functions();
    if (remark::detail::InFlightRemark finished = remark::analysis(
            program.getLoc(), remark::RemarkOpts::name("finished").category("idr-optimize")))
      finished << remark::metric("nodes", set.nodeCount()) << remark::metric("made", scheduler.made())
               << remark::metric("largest", largest) << remark::metric("capped", scheduler.capped());
    // No type changed; every other analysis is stale.
    markAnalysesPreserved<idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
