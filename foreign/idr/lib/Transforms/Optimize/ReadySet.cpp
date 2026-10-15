// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ready set: one node per function of the module, the components of
// its graph, callees first, and what each component waits on. Built once,
// on the pass thread, before the first wave.
//
// A function waits on what it calls and on the labels of the memo sums it
// forces: a force may run any of them, and its effects are theirs. The
// graph's edges are upstream's call graph in its walk order, then the
// forced labels, so the components and their order are a function of the
// module alone.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <utility>

using namespace mlir;

namespace idr::optimize {

Scc &Scc::leader() {
  Scc *at = this;
  while (at->mergedInto) {
    if (at->mergedInto->mergedInto)
      at->mergedInto = at->mergedInto->mergedInto;
    at = at->mergedInto;
  }
  return *at;
}

//===----------------------------------------------------------------------===//
// The ready set
//===----------------------------------------------------------------------===//

namespace {

// What one walk of a body finds: the callee of every call, repeats kept,
// and the labels every force may run.
struct BodySlot {
  SmallVector<StringAttr> callees;
  SmallVector<FuncOp> forced;
};

void walkBody(FuncOp fn, const mlir::SymbolTable &symbols, BodySlot &slot) {
  fn.getBody().walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (auto call = dyn_cast<CallOp>(op))
      slot.callees.push_back(call.getCalleeAttr().getAttr());
    else if (auto force = dyn_cast<ForceOp>(op))
      forcedLabels(force, symbols, slot.forced);
  });
}

} // namespace

ReadySet::ReadySet(Operation *op, AnalysisManager &am) {
  auto module = cast<ModuleOp>(op);
  mlir::SymbolTable &symbols = am.getAnalysis<mlir::SymbolTable>();
  SmallVector<FuncOp> fns(module.getOps<FuncOp>());
  unsigned n = static_cast<unsigned>(fns.size());
  llvm::DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn, static_cast<unsigned>(at));

  // Each body is walked on a worker into its own slot; the merge, in
  // module order, makes the counts and the edges the same however many
  // threads walked.
  SmallVector<BodySlot> slots(n);
  parallelFor(module.getContext(), 0, n,
              [&](size_t at) { walkBody(fns[at], symbols, slots[at]); });

  // calls(f): every call site naming f now, frozen for the run.
  llvm::DenseMap<StringAttr, unsigned> calls;
  for (const BodySlot &slot : slots)
    for (StringAttr callee : slot.callees)
      ++calls[callee];
  for (FuncOp fn : fns) {
    auto node = std::make_unique<Node>();
    node->fn = fn;
    node->facts.calls = calls.lookup(fn.getSymNameAttr());
    byName.try_emplace(fn.getSymNameAttr(), node.get());
    all.push_back(std::move(node));
  }

  // The edges: upstream's call graph, in its walk order, then the labels
  // a force may run, each callee once.
  mlir::CallGraph graph(module);
  SmallVector<SmallVector<unsigned>> successors(n);
  for (unsigned at = 0; at < n; ++at) {
    llvm::SmallDenseSet<unsigned, 8> seen;
    auto edge = [&](Operation *callee) {
      auto found = index.find(callee);
      if (found != index.end() && seen.insert(found->second).second)
        successors[at].push_back(found->second);
    };
    if (CallGraphNode *node = graph.lookupNode(&fns[at].getBody()))
      for (const CallGraphNode::Edge &out : *node)
        if (out.isCall() && !out.getTarget()->isExternal())
          edge(out.getTarget()->getCallableRegion()->getParentOp());
    for (FuncOp label : slots[at].forced)
      edge(label);
  }

  SmallVector<Scc *> sccOf(n, nullptr);
  for (const SmallVector<unsigned> &part : idr::components(successors)) {
    auto scc = std::make_unique<Scc>();
    SmallVector<unsigned> members(part);
    llvm::sort(members);
    for (unsigned at : members) {
      scc->members.push_back(all[at].get());
      all[at]->scc = scc.get();
      sccOf[at] = scc.get();
    }
    sccs.push_back(std::move(scc));
  }
  llvm::DenseSet<std::pair<Scc *, Scc *>> linked;
  for (unsigned at = 0; at < n; ++at) {
    for (unsigned to : successors[at]) {
      Scc *from = sccOf[at], *into = sccOf[to];
      if (from == into || !linked.insert({from, into}).second)
        continue;
      into->callers.push_back(from);
      ++from->unfinishedCallees;
    }
  }
}

ReadySet::~ReadySet() = default;

FuncOp ReadySet::lookup(StringAttr name) const {
  Node *node = byName.lookup(name);
  return node ? node->fn : FuncOp();
}

bool ReadySet::isFinal(FuncOp fn) const {
  Node *node = byName.lookup(fn.getSymNameAttr());
  return node && node->fn == fn && node->isFinal();
}

} // namespace idr::optimize
