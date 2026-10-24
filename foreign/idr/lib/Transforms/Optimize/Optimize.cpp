// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize: the specialize phase over the program, then, every
// function final, the results no caller reads and the captures no dispatch
// reads dropped from the whole program. The functions nothing names any
// more are upstream's symbol-dce's, and the weighed inlining on the final
// graph is idr-inline's, which the pipeline runs after it.
//
// A pass on the program, as upstream's inliner is on its module: leaf
// inlining and the redirect read a sibling of the function they rewrite,
// which a nested pass may not, and the schedule is what makes the read
// safe, since a callee is read only once it is final and nothing writes it
// again. Every rewrite is a pass of the inner pipeline, run with
// runPipeline so that the verifier and the manager's instrumentation run
// on each function as they would under a nest. No greedy rewriter runs:
// the inner pipeline's simplification is the e-graph's.

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Inline.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/OptimizeScheduler.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/SpecializeState.h"

#include "mlir/IR/Remarks.h"
#include "llvm/ADT/Statistic.h"

#define GEN_PASS_DEF_IDROPTIMIZE
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

// A pass statistic must have the layout the MLIR library gives it, which
// holds the count: the pinned LLVM is built with LLVM_FORCE_ENABLE_STATS,
// so its llvm-config.h says statistics count in our build too, and
// idr-optimize's counts are read off them.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

void idr::optimize::buildInnerPipeline(OpPassManager &pm, Schedule &schedule,
                                       specialize::Nodes &nodes, const InnerCounts &counts) {
  pm.addPass(specialize::createRedirect(schedule, nodes, counts.redirected,
                                        specialize::InRound::First));
  pm.addPass(inlining::createInlineLeaves(schedule, counts.inlinedLeaves));
  pm.addPass(createIdrSimplify(schedule.callees));
  pm.addPass(specialize::createRedirect(schedule, nodes, counts.redirected,
                                        specialize::InRound::Last));
}

namespace idr::optimize {

// The schedule and the table are this run's own, and so is the inner
// pipeline every worker copies: each step is made with what it reads of
// them and the statistics it counts into.
struct OptimizePass : impl::IdrOptimizeBase<OptimizePass> {
  LogicalResult runNestedPipeline(OpPassManager &pm, Operation *op) { return runPipeline(pm, op); }

  void runOnProgram(ProgramOp program) {
    auto &graph = getAnalysis<solver::ProgramGraph>();
    Schedule schedule(program, graph);
    specialize::Nodes nodes(schedule);
    schedule.attach(nodes);
    const InnerCounts counts{numRedirected, numInlinedLeaves};
    // Every function's analysis manager exists before any task, so a
    // pipeline's own nesting finds it instead of inserting it.
    for (FuncOp fn : program.getOps<FuncOp>())
      (void)getAnalysisManager().nest(fn);
    // The pass's work: the solves of each component's binding times and of
    // what it gives back, then the rows' join over the final graph.
    solver::Work work;
    Scheduler scheduler(*this, schedule, nodes, counts, getAnalysisManager(), work);
    LogicalResult ran = scheduler.run();
    numNodes += scheduler.made();
    if (failed(ran))
      return signalPassFailure();
    nodes.writeCopies();
    // Every function is final: what no caller reads of a result and no
    // dispatch of a capture goes from the whole program; then the graph is
    // frozen as the schedule left it, and every row is derived on it, so a
    // call says what its callee may now do.
    dropDeadResults(schedule);
    narrowCaptures(schedule);
    std::move(schedule.graph).freeze();
    rows::write(program, graph, work);
    numWork += work.steps();
    if (remark::detail::InFlightRemark finished = remark::analysis(
            program.getLoc(), remark::RemarkOpts::name("finished").category("idr-optimize")))
      finished << remark::metric("functions", graph.size().value())
               << remark::metric("made", scheduler.made());
    markAnalysesPreserved<solver::ProgramGraph>();
  }
};

LogicalResult runNested(OptimizePass &pass, OpPassManager &pm, Operation *op) {
  return pass.runNestedPipeline(pm, op);
}

} // namespace idr::optimize
