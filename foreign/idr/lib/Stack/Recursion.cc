// Which functions may have more than one frame live at a time
// (Stack/Recursion.h).

#include "Stack/Recursion.h"

#include "Passes/Scc.h"
#include "Stack/Tail.h"

#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr::stack {

llvm::DenseSet<Operation *> recursiveFunctions(ModuleOp module) {
  SymbolTable symbols(module);
  SmallVector<Operation *> fns;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      fns.push_back(fn);

  // What an idr.apply may call: every function whose address is taken.
  SetVector<Operation *> labels;
  if (std::optional<SymbolTable::UseRange> uses =
          SymbolTable::getSymbolUses(&module.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (!isa<func::CallOp>(use.getUser()))
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
        if (callee && !callee.isExternal() && !(callee == fn && inTailPosition(call)))
          out.push_back(callee);
      }
      applies |= isa<ApplyOp>(op);
    });
    if (applies)
      llvm::append_range(out, labels);
  }

  llvm::DenseSet<Operation *> recursive;
  for (const SmallVector<Operation *> &component : passes::stronglyConnected<Operation *>(
           fns, [&](Operation *fn) { return calls.lookup(fn); })) {
    Operation *first = component.front();
    if (component.size() > 1 || llvm::is_contained(calls.lookup(first), first))
      recursive.insert(component.begin(), component.end());
  }
  return recursive;
}

} // namespace idr::stack
