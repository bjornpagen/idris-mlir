// Which functions may have more than one frame live at a time, and which
// share a cycle of calls (Stack/Recursion.h).

#include "Stack/Recursion.h"

#include "Passes/Scc.h"
#include "Passes/Tail.h"

#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr::stack {

Cycles::Cycles(ModuleOp module) {
  SymbolTable symbols(module);
  SmallVector<Operation *> fns;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);

  // What an idr.apply may call: every function whose address is taken. A
  // clone names itself (idr.clone), which takes no address.
  SetVector<Operation *> labels;
  if (std::optional<SymbolTable::UseRange> uses =
          SymbolTable::getSymbolUses(&module.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (!isa<func::CallOp, func::FuncOp>(use.getUser()))
        if (auto fn = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference());
            fn && !fn.isExternal())
          labels.insert(fn);

  llvm::DenseMap<Operation *, SmallVector<Operation *>> calls;
  for (Operation *fn : fns) {
    SmallVector<Operation *> &out = calls[fn];
    bool applies = false;
    fn->walk([&](Operation *op) {
      if (auto call = dyn_cast<func::CallOp>(op)) {
        auto callee = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (callee && !callee.isExternal() && !(callee == fn && passes::inTailPosition(call)))
          out.push_back(callee);
      }
      applies |= isa<ApplyOp>(op);
    });
    if (applies)
      llvm::append_range(out, labels);
  }

  unsigned index = 0;
  for (const SmallVector<Operation *> &members : passes::stronglyConnected<Operation *>(
           fns, [&](Operation *fn) { return calls.lookup(fn); })) {
    for (Operation *fn : members)
      component[fn] = index;
    ++index;
    Operation *first = members.front();
    if (members.size() > 1 || llvm::is_contained(calls.lookup(first), first))
      onCycle.insert(members.begin(), members.end());
  }
}

bool Cycles::together(Operation *a, Operation *b) const {
  if (a == b)
    return true;
  auto at = component.find(a), bt = component.find(b);
  return at != component.end() && bt != component.end() && at->second == bt->second;
}

} // namespace idr::stack
