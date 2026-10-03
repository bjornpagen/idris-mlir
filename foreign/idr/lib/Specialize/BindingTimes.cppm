// idr.specialize:bindingtimes: which parameters of a function a call may
// specialize on.
//
// A function is recursive when it is on a cycle of references (the
// functions it calls, and those its closures and closure constants name):
// recursion through a closure counts. A parameter of a recursive function
// is
//   - fixed when every reference to the function from its cycles passes it
//     unchanged in the same position: one clone serves the whole recursion,
//     whose calls then have its key;
//   - decreasing when every such reference passes a proper part of it: a
//     field of it, an argument of a region of a match on it, or its
//     predecessor as a Nat (`idr.big.pred`, defined on non-zero values
//     only); the keys shrink along the chain of clones;
//   - bounded when every such reference passes it or a proper part of it:
//     the keys are parts of the first one;
//   - other otherwise: an accumulator, a counter, a closure rebuilt on every
//     iteration. A call never specializes on it.
//
// The classes are found as Lean's fixed parameters are: each function is
// interpreted over abstract values (a parameter, a proper part of one, or
// anything), and so is every function of its cycles that it reaches, once
// for each assignment of abstract values to its parameters, so the analysis
// ends. They are computed from the module as the pass finds it, before it
// changes anything: a clone the pass makes has none until its next run.
export module idr.specialize:bindingtimes;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :bindingtime;
import :foreachreference;
import :interpreter;

using namespace mlir;

export namespace idr::specialize {

class BindingTimes {
public:
  BindingTimes(mlir::ModuleOp module, mlir::SymbolTable &symbols);

  // The binding time of parameter `index` of `fn`, or none for a function
  // the analysis did not see: one made after it ran.
  std::optional<BindingTime> of(mlir::func::FuncOp fn, unsigned index) const;

private:
  // Every parameter of every function the analysis saw; Free throughout for
  // one on no cycle.
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<BindingTime>> times;
};

} // namespace idr::specialize

namespace idr::specialize {

BindingTimes::BindingTimes(ModuleOp module, SymbolTable &symbols) {
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>()) {
    times[fn.getOperation()].assign(fn.getNumArguments(), BindingTime::Free);
    if (!fn.isExternal())
      functions.push_back(fn);
  }
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> references;
  for (func::FuncOp fn : functions) {
    SmallVector<func::FuncOp> &out = references[fn];
    forEachReference(fn, symbols, [&](func::FuncOp target, Operation *) {
      if (!llvm::is_contained(out, target))
        out.push_back(target);
    });
  }
  for (const SmallVector<func::FuncOp> &component : idr::graph::stronglyConnected<func::FuncOp>(
           functions, [&](func::FuncOp fn) { return references.lookup(fn); })) {
    func::FuncOp first = component.front();
    if (component.size() == 1 && !llvm::is_contained(references.lookup(first), first))
      continue;
    llvm::DenseSet<Operation *> cycle;
    for (func::FuncOp fn : component)
      cycle.insert(fn.getOperation());
    for (func::FuncOp fn : component)
      times[fn.getOperation()] = Interpreter(fn, cycle, symbols).run();
  }
}

std::optional<BindingTime> BindingTimes::of(func::FuncOp fn, unsigned index) const {
  auto it = times.find(fn.getOperation());
  if (it == times.end())
    return std::nullopt;
  return it->second[index];
}

} // namespace idr::specialize
