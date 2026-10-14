// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which functions share a cycle of calls, for the escape analysis's tail
// rule and the frame budget. A call names its callee, and an idr.apply may
// call any function whose address is taken (a closure, a closure constant,
// or any other use of its symbol but a call's callee).
#include "idr/Analysis/Escapes.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr {

void Escapes::findCycles(ModuleOp top, SymbolTable &symbols) {
  SmallVector<Operation *> fns;
  for (FuncOp fn : top.getOps<FuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);

  // What an idr.apply may call: every function whose address is taken. A
  // clone names itself in its own facts, which takes no address.
  llvm::SetVector<Operation *> labels;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&top.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (!isa<CallOp, FuncOp>(use.getUser()))
        if (auto fn = symbols.lookup<FuncOp>(use.getSymbolRef().getRootReference());
            fn && !fn.isExternal())
          labels.insert(fn);

  // Each function's callees, one slot per function: a walk of its own body
  // and lookups in a table nothing writes meanwhile. A function's call of
  // itself in tail position is no edge: idr-tail-loops makes it the next
  // iteration of a loop in the same frame.
  SmallVector<SmallVector<Operation *>> calls(fns.size());
  parallelFor(top.getContext(), 0, fns.size(), [&](size_t at) {
    Operation *fn = fns[at];
    bool applies = false;
    fn->walk([&](Operation *op) {
      if (auto call = dyn_cast<CallOp>(op)) {
        auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
        if (callee && !callee.isExternal() &&
            !(callee.getOperation() == fn && tail::inTailPosition(call)))
          calls[at].push_back(callee);
      }
      applies |= isa<ApplyOp>(op);
    });
    if (applies)
      llvm::append_range(calls[at], labels);
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
