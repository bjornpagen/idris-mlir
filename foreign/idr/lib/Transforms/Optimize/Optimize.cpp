// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize: the ready set over the program, then the functions nothing
// names any more erased, serially, in program order.
//
// A pass on the program, as upstream's inliner is on its module: inlining
// reads a sibling of the function it rewrites, which a nested pass may
// not, and the ready set is what makes the read safe, since a callee is
// read only once it is final and nothing writes it again. Every other
// rewrite is a pass of the inner pipeline, run with runPipeline so that
// the verifier and the manager's instrumentation run on each function as
// they would under a nest. The analyses those passes read are taken here,
// before any task, so that each finds its program's through its parent's
// cache: the ready set, which holds every summary.

#include "idr/Analysis/Holds.h"
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
#include "mlir/IR/Threading.h"
#include "mlir/Transforms/Passes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
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

void idr::optimize::buildInnerPipeline(OpPassManager &pm) {
  // Before canonicalization, on what the component solved when it was
  // taken up: a call of a function that only rebuilds its argument is gone
  // before anything weighs it.
  pm.addPass(idr::createIdrIdentity());
  pm.addPass(idr::createCanonicalizerPass());
  // A call is opaque to canonicalize and CSE, which cannot read its callee;
  // the summaries can, so the calls of pure callees go or merge here, and
  // CSE then merges what their operands' merging made equal.
  pm.addPass(idr::optimize::createPureCallsPass());
  pm.addPass(createCSEPass());
  // On what canonicalization and CSE left: a call whose arguments are
  // known constructors asks for its specialization and calls it.
  pm.addPass(idr::createIdrRedirect());
  // Last, so that the body a caller's summary is read from is the one this
  // solve left.
  pm.addPass(idr::createIdrConstants());
}

namespace {

// Erases every function no symbol use reaches from the root, in program
// order; how many. Each function's uses, upstream's (its attributes and
// its body's), are read on a worker into a slot of its own, and the reach
// is taken from the slots. Each function joins the live set once, so the
// reach ends.
unsigned eraseDead(idr::ProgramOp program, SymbolTable &symbols) {
  SmallVector<idr::FuncOp> fns(program.getOps<idr::FuncOp>());
  llvm::DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn, static_cast<unsigned>(at));
  SmallVector<SmallVector<unsigned>> uses(fns.size());
  parallelFor(program.getContext(), 0, fns.size(), [&](size_t at) {
    llvm::SmallDenseSet<unsigned, 8> seen;
    std::optional<SymbolTable::UseRange> found =
        SymbolTable::getSymbolUses(fns[at].getOperation());
    assert(found && "an idr.func holds no op that may hold a symbol table unknown to it");
    for (const SymbolTable::SymbolUse &use : *found) {
      auto target = symbols.lookup<idr::FuncOp>(use.getSymbolRef().getRootReference());
      if (!target)
        continue;
      unsigned to = index.lookup(target);
      if (seen.insert(to).second)
        uses[at].push_back(to);
    }
  });
  auto root = symbols.lookup<idr::FuncOp>(program.getRoot());
  assert(root && "a verified program's root is one of its functions");
  SmallVector<bool> live(fns.size(), false);
  unsigned start = index.lookup(root);
  live[start] = true;
  SmallVector<unsigned> work{start};
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
    if (live[at])
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
    idr::ProgramOp program = getOperation();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    const idr::Holds &holds = getAnalysis<idr::Holds>();
    const idr::specialize::Nodes &nodes = getAnalysis<idr::specialize::Nodes>();
    idr::optimize::ReadySet &set = getAnalysis<idr::optimize::ReadySet>();
    // The ready set is the node table's schedule and its binding times.
    nodes.start(set, set, holds);
    // Every function's analysis manager exists before any task, so a
    // pipeline's own nesting finds it instead of inserting it.
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      (void)getAnalysisManager().nest(fn);

    idr::optimize::Scheduler scheduler(
        {program, set, symbols, nodes, getAnalysisManager()},
        [this](OpPassManager &pm, Operation *op) { return runPipeline(pm, op); });
    LogicalResult ran = scheduler.run();
    numInlined += scheduler.inlined();
    numCapped += scheduler.capped();
    numNodes += scheduler.made();
    if (failed(ran))
      return signalPassFailure();

    int64_t largest = 0;
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>())
      if (idr::optimize::Node *node = set.nodeOf(fn.getSymNameAttr()))
        largest = std::max(largest, node->summary.facts.size);
    unsigned erased = eraseDead(program, symbols);
    numErased += erased;
    if (remark::detail::InFlightRemark finished = remark::analysis(
            program.getLoc(), remark::RemarkOpts::name("finished").category("idr-optimize")))
      finished << remark::metric("nodes", set.nodeCount()) << remark::metric("made", scheduler.made())
               << remark::metric("largest", largest) << remark::metric("capped", scheduler.capped());
    // No type changed; every other analysis, the ready set that held this
    // run's summaries included, is stale.
    markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
