// idr.ownership:borrowed: whether a function borrows a parameter.
export module idr.ownership:borrowed;

import idr.mlir;
import idr.dialect;

import :stage;

using namespace mlir;

namespace idr::ownership {

// Whether the function borrows its parameter `index`: in the owned
// stage, whether the parameter is a view. Before the owned stage every
// parameter may still be owned: borrow inference has not decided.
export bool isBorrowed(func::FuncOp fn, unsigned index) {
  auto module = fn->getParentOfType<ModuleOp>();
  return module && module->hasAttr(stageAttr) && index < fn.getNumArguments() &&
         !isOwned(fn.getArgument(index).getType());
}

} // namespace idr::ownership
