// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize: the ready set over the module, then the functions nothing
// names any more erased, serially, in module order.
//
// A module pass, as upstream's inliner is: inlining reads a sibling of the
// function it rewrites, which a nested pass may not, and the ready set is
// what makes the read safe, since a callee is read only once it is final
// and nothing writes it again. Every other rewrite is a pass of the inner
// pipeline, run with runPipeline so that the verifier and the manager's
// instrumentation run on each function as they would under a nest. The
// analyses those passes read are taken here, before any task, so that
// each finds its module's through its parent's cache.

#include "idr/Analysis/Constants.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Identities.h"
#include "idr/Analysis/References.h"
#include "idr/Analysis/Specialize.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Identity.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/IR/Remarks.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
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
// idr-optimize's counts of what it inlined, capped, erased and made are
// read off them.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

void idr::optimize::buildInnerPipeline(OpPassManager &pm) {
  // Before canonicalization, on the effects the component's call sites
  // were given when it was taken up: a call of a function that only
  // rebuilds its argument is gone before anything weighs it.
  pm.addPass(idr::createIdrIdentity());
  pm.addPass(idr::createCanonicalizerPass());
  pm.addPass(createCSEPass());
  // On what canonicalization and CSE left: a call whose arguments are
  // known constructors asks for its specialization and calls it.
  pm.addPass(idr::createIdrRedirect());
  pm.addPass(arith::createIntRangeOptimizationsPass());
  // Last, so that the body a caller's summary is read from is the one this
  // solve left.
  pm.addPass(idr::createIdrConstants());
}

namespace {

// Erases every private function no symbol use reaches from a public one,
// in module order; how many. Each body's uses are read on a worker into a
// slot of its own, and the reach is taken from the slots in module order.
unsigned eraseDead(ModuleOp module, SymbolTable &symbols) {
  SmallVector<idr::FuncOp> fns(module.getOps<idr::FuncOp>());
  llvm::DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn, static_cast<unsigned>(at));
  SmallVector<SmallVector<unsigned>> uses(fns.size());
  parallelFor(module.getContext(), 0, fns.size(), [&](size_t at) {
    llvm::SmallDenseSet<unsigned, 8> seen;
    fns[at].getBody().walk([&](Operation *op) {
      idr::walkStoredAttributes(op, [&](Attribute attr) {
        auto ref = dyn_cast<FlatSymbolRefAttr>(attr);
        auto target = ref ? symbols.lookup<idr::FuncOp>(ref.getAttr()) : idr::FuncOp();
        if (!target)
          return;
        unsigned to = index.lookup(target);
        if (seen.insert(to).second)
          uses[at].push_back(to);
      });
    });
  });
  SmallVector<bool> live(fns.size(), false);
  SmallVector<unsigned> work;
  for (auto [at, fn] : llvm::enumerate(fns)) {
    if (!fn.isPublic())
      continue;
    live[at] = true;
    work.push_back(static_cast<unsigned>(at));
  }
  while (!work.empty()) {
    unsigned at = work.pop_back_val();
    for (unsigned to : uses[at]) {
      if (live[to])
        continue;
      live[to] = true;
      work.push_back(to);
    }
  }
  unsigned erased = 0;
  for (auto [at, fn] : llvm::enumerate(fns)) {
    if (live[at] || fn.isPublic())
      continue;
    symbols.erase(fn);
    ++erased;
  }
  return erased;
}

struct Optimize : idr::impl::IdrOptimizeBase<Optimize> {
  // A pipeline run from inside a pass loads no dialect, so the inner
  // pipeline's are loaded before the manager runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    IdrOptimizeBase::getDependentDialects(registry);
    OpPassManager pm(idr::FuncOp::getOperationName());
    idr::optimize::buildInnerPipeline(pm);
    pm.getDependentDialects(registry);
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const idr::Holds &holds = getAnalysis<idr::Holds>();
    idr::ConstantSummaries &summaries = getAnalysis<idr::ConstantSummaries>();
    idr::BindingTimes &times = getAnalysis<idr::BindingTimes>();
    idr::Identities &identities = getAnalysis<idr::Identities>();
    const idr::specialize::Nodes &nodes = getAnalysis<idr::specialize::Nodes>();
    idr::optimize::ReadySet &set = getAnalysis<idr::optimize::ReadySet>();
    nodes.start(set, times, holds);
    // Every function's analysis manager exists before any task, so a
    // pipeline's own nesting finds it instead of inserting it.
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
      (void)getAnalysisManager().nest(fn);

    idr::optimize::Scheduler scheduler(
        {module, set, symbols, holds, summaries, times, identities, nodes, getAnalysisManager()},
        [this](OpPassManager &pm, Operation *op) { return runPipeline(pm, op); });
    LogicalResult ran = scheduler.run();
    numInlined += scheduler.inlined();
    numCapped += scheduler.capped();
    numNodes += scheduler.made();
    if (failed(ran))
      return signalPassFailure();

    int64_t largest = 0;
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
      if (idr::optimize::Node *node = set.nodeOf(fn.getSymNameAttr()))
        largest = std::max(largest, node->facts.size);
    unsigned erased = eraseDead(module, symbols);
    numErased += erased;
    if (remark::detail::InFlightRemark finished = remark::analysis(
            module.getLoc(), remark::RemarkOpts::name("finished").category("idr-optimize")))
      finished << remark::metric("nodes", set.nodeCount()) << remark::metric("made", scheduler.made())
               << remark::metric("largest", largest) << remark::metric("capped", scheduler.capped());
    // No type changed; every other analysis, the ready set and the
    // summaries of this run included, is stale.
    markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
