// idr.ownership:ownsignatures: the signatures counting assumes when borrow
// inference does not run.
export module idr.ownership:ownsignatures;

import idr.mlir;
import idr.dialect;

import :counting;

using namespace mlir;

namespace idr::ownership {

// The signatures with every parameter and result that holds references
// owned: what counting assumes when borrow inference does not run.
export void ownSignatures(ModuleOp module, Counting &counting) {
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    SmallVector<Type> params;
    for (BlockArgument arg : fn.getArguments()) {
      if (counting.counted(arg.getType()))
        arg.setType(idr::owned(arg.getType()));
      params.push_back(arg.getType());
    }
    SmallVector<Type> results;
    for (Type result : fn.getResultTypes())
      results.push_back(counting.counted(result) ? idr::owned(result) : result);
    fn.setFunctionType(FunctionType::get(module.getContext(), params, results));
  }
}

} // namespace idr::ownership
