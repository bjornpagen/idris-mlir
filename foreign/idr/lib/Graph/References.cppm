// idr.graph:references: what each function's body refers to, and how large
// the body is, from one walk of that body. The passes that follow calls
// and closures ask the same questions of every function, and an
// interpretation of a cycle asks them again for every assignment of
// abstract values: walking each body once answers them. A reference is the
// callee of a call, the label of a closure, or the label of a closure
// constant, in the order the walk meets them; the first reference to a
// function is the edge the cycles see. An apply calls something and names
// no function, so it is not a reference.
export module idr.graph:references;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::graph {

class References {
public:
  // One reference: `target` is named by `at`.
  struct Site {
    func::FuncOp target;
    Operation *at = nullptr;
  };

  // The references of every function that has a body. Valid until the
  // module changes.
  References(ModuleOp module, SymbolTable &symbols);

  // The references of `fn`, in walk order, and none when it has no body.
  ArrayRef<Site> of(func::FuncOp fn) const;

  // Whether the body of `fn` holds a call, an apply included.
  bool hasCall(func::FuncOp fn) const;

  // How many operations the body of `fn` holds: what a walk of it counts.
  int64_t ops(func::FuncOp fn) const;

private:
  DenseMap<Operation *, SmallVector<Site>> sites;
  DenseMap<Operation *, int64_t> sizes;
  DenseSet<Operation *> callers;
};

} // namespace idr::graph

namespace idr::graph {

References::References(ModuleOp module, SymbolTable &symbols) {
  for (func::FuncOp fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    int64_t n = 0;
    fn.getBody().walk([&](Operation *op) {
      ++n;
      if (isa<CallOpInterface>(op))
        callers.insert(fn.getOperation());
      if (auto call = dyn_cast<func::CallOp>(op)) {
        if (auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
          sites[fn.getOperation()].push_back({target, op});
        return;
      }
      if (auto closure = dyn_cast<idr::ClosureOp>(op)) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCalleeAttr().getAttr()))
          sites[fn.getOperation()].push_back({target, op});
        return;
      }
      if (auto suspend = dyn_cast<idr::SuspendOp>(op)) {
        if (auto target = symbols.lookup<func::FuncOp>(suspend.getCalleeAttr().getAttr()))
          sites[fn.getOperation()].push_back({target, op});
        return;
      }
      op->getAttrDictionary().walk([&](idr::ClosureAttr closure) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()))
          sites[fn.getOperation()].push_back({target, op});
      });
    });
    sizes[fn.getOperation()] = n;
  }
}

ArrayRef<References::Site> References::of(func::FuncOp fn) const {
  auto it = sites.find(fn.getOperation());
  if (it == sites.end())
    return {};
  return it->second;
}

bool References::hasCall(func::FuncOp fn) const { return callers.contains(fn.getOperation()); }

int64_t References::ops(func::FuncOp fn) const { return sizes.lookup(fn.getOperation()); }

} // namespace idr::graph
