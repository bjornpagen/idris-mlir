// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-defunctionalize, on the program as the frontend wrote it: no
// optimization runs before it, so the label solve reads the program's own
// flow, and the families it decides are the ones idr-knots then judges.
//
// The solve finds every slot's labels, with no unknown, so every key
// becomes a family: the pass refuses nothing, a run-time choice among the
// implementations the program fixes included, which is a closed sum like
// any other, and it fails only when the compiler broke its own invariant.
// The program graph is born here, over the program's calls; the decision
// gives it each run of labels as a call of each label it runs, and reads
// off the one join of rows over it which labels' runs read or write the
// outside. Such a label runs by name in its memo family: memoizing it would
// run its effect at the first demand only. A crash, an exit or a loop
// happens once whoever demands it, so only the outside decides.
//
// Then the decision is made whole, serially, every type and attribute the
// edits build with it, and each function makes its edits on its own, in
// parallel, reading it. The program is first-order after it, and every
// call of it takes its tail fact from the one definition, in one walk:
// every run is a call of its own, so the graph takes the dispatch functions,
// and the row of each function that ran labels or whose facts changed,
// again from their calls, and every row is derived over it.

#include "idr/Analysis/Labels.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Optimize/Tails.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Threading.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

using idr::optimize::Facts;

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnProgram(idr::ProgramOp program) {
    const idr::Labels &labels = getAnalysis<idr::Labels>();
    idr::solver::ProgramGraph &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::solver::Work spent;
    FailureOr<std::unique_ptr<idr::defunctionalize::Decision>> decision =
        idr::defunctionalize::Decision::decide(program, labels, graph, spent);
    if (failed(decision))
      return signalPassFailure();
    const idr::defunctionalize::Decision &decided = **decision;
    // The functions the program had, each with its edits; the dispatch
    // functions the decision added are born rewritten.
    parallelForEach(&getContext(), decided.edits(), [&](const idr::defunctionalize::Edits &edits) {
      idr::defunctionalize::rewrite(edits, decided);
    });
    numFamilies += decided.numFamilies();
    // The program is first order: every call of it, each run's among them,
    // takes its tail fact where it stands, in one walk, each function's
    // calls on their own, in parallel: the functions the program had, then
    // the dispatch functions.
    idr::footprint::Vector<idr::FuncOp> functions;
    for (const idr::defunctionalize::Edits &edits : decided.edits())
      functions.push_back(edits.fn);
    std::size_t had = functions.size();
    functions.insert(functions.end(), decided.forces().begin(), decided.forces().end());
    idr::footprint::Vector<Facts> facts(functions.size(), Facts::Kept);
    parallelFor(&getContext(), 0, functions.size(),
                [&](std::size_t at) { facts[at] = idr::optimize::decideTails(functions[at]); });
    // Each dispatch function joins the graph, and its row, and the row of
    // each function whose calls changed (its runs became calls, or a fact
    // did), are read from their calls, each turn writing its own function's
    // row.
    {
      idr::IndexVector<idr::solver::FunctionId, Facts> ran = graph.table<Facts>(Facts::Kept);
      for (const idr::defunctionalize::Runner &each : decided.runners())
        ran[each.id] = Facts::Changed;
      idr::footprint::Vector<idr::defunctionalize::Runner> reread;
      for (std::size_t at = 0; at < had; ++at)
        if (idr::solver::FunctionId id = graph.id(functions[at]);
            facts[at] == Facts::Changed || ran[id] == Facts::Changed)
          reread.push_back({id, functions[at]});
      idr::solver::Editor editor = graph.thaw();
      for (std::size_t at = had; at < functions.size(); ++at)
        reread.push_back({editor.insert(functions[at]), functions[at]});
      parallelForEach(&getContext(), reread, [&](const idr::defunctionalize::Runner &each) {
        editor.setCallees(each.id, idr::solver::rowOf(each.fn, editor));
      });
      std::move(editor).freeze();
    }
    // The program is first-order: every function's row and every call's
    // are derived over its graph.
    idr::rows::write(program, graph, spent);
    // The pass's work: the label solve's, and the rows' two joins.
    numWork += labels.work() + spent.steps();
    markAnalysesPreserved<idr::solver::ProgramGraph>();
  }
};

} // namespace
