// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ready set: one node per function of the program, the components of
// its call graph, callees first, and what each component waits on. Built
// once, on the pass thread, before the first wave.
//
// A function waits on what it calls. Once the program is first-order that
// is all it runs, a force being a call of its memo sum's dispatch function,
// so upstream's call graph is the whole graph: the components and their
// order are its, a function of the program alone.

#include "idr/Transforms/Optimize.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <utility>

using namespace mlir;

namespace idr::optimize {

ReadySet::ReadySet(ProgramOp program) {
  SmallVector<FuncOp> fns(program.getOps<FuncOp>());
  unsigned n = static_cast<unsigned>(fns.size());
  llvm::DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index.try_emplace(fn, static_cast<unsigned>(at));

  // calls(f): every call site naming f now, frozen for the run. Each body
  // is counted on a worker into its own slot; the merge, in program order,
  // makes the counts the same however many threads counted.
  SmallVector<SmallVector<StringAttr>> callees(n);
  parallelFor(program.getContext(), 0, n, [&](size_t at) {
    fns[at].getBody().walk([&](CallOp call) { callees[at].push_back(call.getCalleeAttr().getAttr()); });
  });
  llvm::DenseMap<StringAttr, unsigned> calls;
  for (const SmallVector<StringAttr> &slot : callees)
    for (StringAttr callee : slot)
      ++calls[callee];

  // The components first, so that each node is made in its own; its
  // members come in program order.
  mlir::CallGraph graph(program);
  SmallVector<Scc *> sccOf(n);
  for (const SmallVector<FuncOp> &part : callGraphComponents(graph)) {
    auto scc = std::make_unique<Scc>();
    scc->order = static_cast<unsigned>(sccs.size());
    for (FuncOp fn : part)
      sccOf[index.at(fn)] = scc.get();
    sccs.push_back(std::move(scc));
  }
  for (auto [fn, scc] : llvm::zip_equal(fns, sccOf)) {
    auto node = std::make_unique<Node>(fn, Node::Held{calls.lookup(fn.getSymNameAttr())}, *scc);
    scc->members.push_back(node.get());
    byName.try_emplace(fn.getSymNameAttr(), node.get());
    all.push_back(std::move(node));
  }
  llvm::DenseSet<std::pair<Scc *, Scc *>> linked;
  for (unsigned at = 0; at < n; ++at) {
    CallGraphNode *node = graph.lookupNode(&fns[at].getBody());
    for (const CallGraphNode::Edge &out : *node) {
      if (!out.isCall() || out.getTarget()->isExternal())
        continue;
      Scc *from = sccOf[at];
      Scc *into = sccOf[index.at(out.getTarget()->getCallableRegion()->getParentOp())];
      if (from == into || !linked.insert({from, into}).second)
        continue;
      into->callers.push_back(from->members.front());
      ++from->unfinishedCallees;
    }
  }
}

ReadySet::~ReadySet() = default;

FuncOp ReadySet::lookup(StringAttr name) const {
  Node *node = byName.lookup(name);
  return node ? node->fn : FuncOp();
}

FuncOp ReadySet::finalFunction(StringAttr name) const {
  Node *node = byName.lookup(name);
  return node && node->isFinal() ? node->fn : FuncOp();
}

bool ReadySet::sameComponent(StringAttr a, StringAttr b) const {
  Node *x = byName.lookup(a), *y = byName.lookup(b);
  return x && y && x->sharesComponentWith(*y);
}

const Summary *ReadySet::summaryOf(StringAttr name) const {
  Node *node = byName.lookup(name);
  return node ? node->summary() : nullptr;
}

ArrayRef<BindingTime> ReadySet::of(StringAttr fn) const {
  const Summary *summary = summaryOf(fn);
  assert(summary && "binding times are read of a final function");
  return summary->times;
}

// A final callee's is its summary's; one of the reader's own component's,
// what the component solved when it took the callee up.
std::optional<unsigned> ReadySet::givesBack(const Node &reader, StringAttr callee) const {
  Node *node = byName.lookup(callee);
  if (!node)
    return std::nullopt;
  if (const Summary *summary = node->summary())
    return summary->givesBack;
  if (!node->sharesComponentWith(reader))
    return std::nullopt;
  return node->solved ? node->solved->givesBack : std::nullopt;
}

} // namespace idr::optimize
