// idr.stack:recursion: which functions may have more than one frame live
// at a time, and which share a cycle of calls.
export module idr.stack:recursion;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;

export namespace idr::stack {

// The cycles of calls among the functions of `module`: a call names its
// callee, and an idr.apply may call any function whose address is taken (a
// closure, a closure constant, or any other use of its symbol but a call's
// callee).
class Cycles {
public:
  explicit Cycles(mlir::ModuleOp module);

  // Whether `fn` is on a cycle of calls, so that it may have more than one
  // frame live at a time. A function's call of itself in tail position does
  // not count: idr-tail-loops makes it the next iteration of a loop in the
  // same frame. A function on no cycle has at most one frame on the stack
  // at a time.
  bool recursive(mlir::Operation *fn) const;

  // Whether `a` and `b` are on one cycle of calls: each may call the other,
  // through any calls. A function is on one with itself.
  bool together(mlir::Operation *a, mlir::Operation *b) const;

private:
  llvm::DenseMap<mlir::Operation *, unsigned> component;
  llvm::DenseSet<mlir::Operation *> onCycle;
};

} // namespace idr::stack

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
        if (callee && !callee.isExternal() && !(callee == fn && graph::inTailPosition(call)))
          out.push_back(callee);
      }
      applies |= isa<ApplyOp>(op);
    });
    if (applies)
      llvm::append_range(out, labels);
  }

  unsigned index = 0;
  for (const SmallVector<Operation *> &members : graph::stronglyConnected<Operation *>(
           fns, [&](Operation *fn) { return calls.lookup(fn); })) {
    for (Operation *fn : members)
      component[fn] = index;
    ++index;
    Operation *first = members.front();
    if (members.size() > 1 || llvm::is_contained(calls.lookup(first), first))
      onCycle.insert(members.begin(), members.end());
  }
}

bool Cycles::recursive(Operation *fn) const { return onCycle.contains(fn); }

bool Cycles::together(Operation *a, Operation *b) const {
  if (a == b)
    return true;
  auto at = component.find(a), bt = component.find(b);
  return at != component.end() && bt != component.end() && at->second == bt->second;
}

} // namespace idr::stack
