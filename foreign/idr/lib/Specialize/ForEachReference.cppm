// idr.specialize:foreachreference: the functions a body refers to:
// callees, closure labels and the labels of closure constants, which the
// binding times follow. Nothing here is exported.
export module idr.specialize:foreachreference;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::specialize {

// Calls `refer(target, op)` for each function the body of `fn` refers to:
// the callee of a call, the label of a closure, and the label of each
// closure constant, in op order.
void forEachReference(func::FuncOp fn, SymbolTable &symbols,
                      llvm::function_ref<void(func::FuncOp, Operation *)> refer) {
  fn.getBody().walk([&](Operation *op) {
    if (auto call = dyn_cast<func::CallOp>(op)) {
      if (auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
        refer(target, op);
      return;
    }
    if (auto closure = dyn_cast<ClosureOp>(op)) {
      if (auto target = symbols.lookup<func::FuncOp>(closure.getCalleeAttr().getAttr()))
        refer(target, op);
      return;
    }
    op->getAttrDictionary().walk([&](ClosureAttr closure) {
      if (auto target = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()))
        refer(target, op);
    });
  });
}

} // namespace idr::specialize
