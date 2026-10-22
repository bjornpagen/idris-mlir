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
// Before the families are declared, the labels whose runs read or write the
// outside are found: a label's own ops, its calls and the labels its
// applies and forces run, followed backwards from every function whose own
// ops touch the outside. Such a label runs by name in its memo family:
// memoizing it would run its effect at the first demand only. A crash, an
// exit or a loop happens once whoever demands it, so only the outside
// decides.
//
// Then the decision is made whole, serially, and each function rewritten
// on its own, in parallel, reading it. The program is first-order after it:
// its program graph is built on its calls, and every row derived over it.

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Labels.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// A function's own atoms, its calls and its runs of labels read apart: the
// by-name question joins them over the program's runs itself.
struct OwnOps {
  void call(idr::CallOp, idr::rows::Fold &, idr::rows::Runs) {}
  idr::rows::Read other(Operation *op, idr::rows::Fold &, idr::rows::Runs) {
    return isa<idr::RunsLabelsOpInterface>(op) ? idr::rows::Read::ByReader
                                                : idr::rows::Read::ByDeclaration;
  }
};

// The functions whose runs reach the outside: each function whose own ops
// read or write it, and every function that calls one or runs one as a
// label, followed backwards. A marking, so its state is a bit per function
// and it ends when no function is newly marked.
llvm::DenseSet<StringAttr> observedRuns(idr::ProgramOp program, const idr::Labels &labels) {
  SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
  llvm::DenseMap<StringAttr, unsigned> position;
  for (auto [at, fn] : llvm::enumerate(fns))
    position.try_emplace(fn.getSymNameAttr(), static_cast<unsigned>(at));
  // Each function's own reach of the outside, and what it runs, each read
  // on a worker into its own slot.
  SmallVector<std::uint8_t> outside(fns.size(), 0);
  SmallVector<SmallVector<unsigned>> runs(fns.size());
  parallelFor(program.getContext(), 0, fns.size(), [&](size_t at) {
    OwnOps reader;
    outside[at] = idr::rows::derive(fns[at], reader).atoms.contains(idr::effects::Atom::io);
    fns[at].walk([&](Operation *op) {
      if (auto call = dyn_cast<idr::CallOp>(op))
        runs[at].push_back(position.find(call.getCalleeAttr().getAttr())->second);
      else if (auto runner = dyn_cast<idr::RunsLabelsOpInterface>(op))
        for (auto label : labels.runs(runner).getAsRange<FlatSymbolRefAttr>())
          runs[at].push_back(position.find(label.getAttr())->second);
    });
  });
  SmallVector<SmallVector<unsigned>> callers(fns.size());
  for (auto [at, out] : llvm::enumerate(runs))
    for (unsigned callee : out)
      callers[callee].push_back(static_cast<unsigned>(at));
  SmallVector<unsigned> work;
  for (auto [at, reaches] : llvm::enumerate(outside))
    if (reaches)
      work.push_back(static_cast<unsigned>(at));
  while (!work.empty()) {
    unsigned at = work.pop_back_val();
    for (unsigned caller : callers[at])
      if (!outside[caller]) {
        outside[caller] = 1;
        work.push_back(caller);
      }
  }
  llvm::DenseSet<StringAttr> observed;
  for (auto [fn, reaches] : llvm::zip_equal(fns, outside))
    if (reaches)
      observed.insert(fn.getSymNameAttr());
  return observed;
}

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnProgram(idr::ProgramOp program) {
    const idr::Labels &labels = getAnalysis<idr::Labels>();
    llvm::DenseSet<StringAttr> byName = observedRuns(program, labels);
    // The functions the program had: the decision adds a dispatch function
    // per memo family, born rewritten.
    SmallVector<idr::FuncOp> functions(program.getOps<idr::FuncOp>());
    FailureOr<std::unique_ptr<idr::defunctionalize::Decision>> decision =
        idr::defunctionalize::Decision::decide(program, labels, byName);
    if (failed(decision))
      return signalPassFailure();
    const idr::defunctionalize::Decision &decided = **decision;
    if (failed(failableParallelForEach(&getContext(), functions, [&](idr::FuncOp fn) {
          return idr::defunctionalize::rewrite(fn, decided);
        })))
      return signalPassFailure();
    numFamilies += decided.numFamilies();
    // The program is first-order: its graph sees every call, and every
    // function's row and every call's are derived over it.
    const auto &graph = getAnalysis<idr::solver::ProgramGraph>();
    idr::solver::Work joining;
    idr::rows::write(program, graph, joining);
    // The pass's work: the label solve's and the rows' join.
    numWork += labels.work() + joining.steps();
    markAnalysesPreserved<idr::solver::ProgramGraph>();
  }
};

} // namespace
