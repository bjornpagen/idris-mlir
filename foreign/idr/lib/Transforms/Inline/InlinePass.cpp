// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-inline: inlining once, on the final program graph, with every call
// site of each callee counted, on upstream's inliner: the verdict is its
// profitability and the e-graph its simplification of every function it
// inlined into. A function enters the simplification only while its
// e-graph's arena fits beside those running, so a small host compiles more
// slowly and never differently.
//
// MLton's rule weighs a callee by its size and its calls, which only the
// final graph counts: specialization is over, so no call is made after the
// count. A call the verdict keeps is a call, and the inliner refuses
// nothing.

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Memory.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Inline.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Transforms/Inliner.h"

namespace idr {
#define GEN_PASS_DEF_IDRINLINE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Inline : idr::impl::IdrInlineBase<Inline> {
  void runOnProgram(idr::ProgramOp program) {
    const auto &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::inlining::Profitability profitability(graph);
    idr::optimize::Admission admission(idr::support::hostMemoryBytes());
    InlinerConfig config;
    config.setDefaultPipeline([](OpPassManager &pm) { pm.addPass(idr::createIdrSimplify()); });
    // Upstream asks from its own workers; each run is admitted by the arena
    // of the function it simplifies.
    auto runPipeline = [&](Pass &, OpPassManager &pm, Operation *op) {
      std::uint64_t arena = idr::egraph::arenaBytes(
          static_cast<std::uint64_t>(idr::inlining::bodyOf(cast<idr::FuncOp>(op)).size));
      admission.enter(arena);
      LogicalResult ran = this->runPipeline(pm, op);
      admission.leave(arena);
      return ran;
    };
    CallGraph &calls = getAnalysis<CallGraph>();
    Inliner inliner(program, calls, *this, getAnalysisManager(), runPipeline, config,
                    [&](const Inliner::ResolvedCall &call) { return profitability(call); });
    if (failed(inliner.doInlining()))
      return signalPassFailure();
    numInlined += profitability.inlined();
    numCapped += profitability.capped();
    // The calls changed: the graph is built anew on them, and every row
    // derived over it, the join the pass's work.
    getAnalysisManager().invalidate(AnalysisManager::PreservedAnalyses());
    const auto &fresh = getAnalysis<idr::solver::ProgramGraph>();
    idr::solver::Work joining;
    idr::rows::write(program, fresh, joining);
    numWork += joining.steps();
    markAnalysesPreserved<idr::solver::ProgramGraph>();
  }
};

} // namespace
