// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which functions share a cycle of calls, for the escape analysis's tail
// rule and the frame budget. A call names its callee.
#include "idr/Analysis/Escapes.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

void Escapes::findCycles(ModuleOp top, SymbolTable &symbols) {
  SmallVector<Operation *> fns;
  for (FuncOp fn : top.getOps<FuncOp>())
    fns.push_back(fn);

  // Each function's callees, one slot per function: a walk of its own body
  // and lookups in a table nothing writes meanwhile. A function's call of
  // itself in tail position is no edge: idr-tail-loops makes it the next
  // iteration of a loop in the same frame.
  SmallVector<SmallVector<Operation *>> calls(fns.size());
  parallelFor(top.getContext(), 0, fns.size(), [&](size_t at) {
    Operation *fn = fns[at];
    fn->walk([&](CallOp call) {
      auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
      if (!(callee.getOperation() == fn && tail::inTailPosition(call)))
        calls[at].push_back(callee);
    });
  });

  DenseMap<Operation *, unsigned> index;
  for (auto [at, fn] : llvm::enumerate(fns))
    index[fn] = static_cast<unsigned>(at);
  auto callees = [&](Operation *fn) { return calls[index.lookup(fn)]; };
  unsigned number = 0;
  for (const SmallVector<Operation *> &members : stronglyConnected<Operation *>(fns, callees)) {
    for (Operation *fn : members)
      component[fn] = number;
    ++number;
    Operation *first = members.front();
    if (members.size() > 1 || llvm::is_contained(callees(first), first))
      onCycle.insert(members.begin(), members.end());
  }
}

bool Escapes::recursive(FuncOp fn) const { return onCycle.contains(fn.getOperation()); }

} // namespace idr
