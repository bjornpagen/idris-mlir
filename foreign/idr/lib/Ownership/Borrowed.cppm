// idr.ownership:borrowed: whether a function borrows a parameter.
export module idr.ownership:borrowed;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Whether the function borrows its parameter `index`: in the owned stage,
// whether the parameter is a view. Before it every parameter may still be
// owned: borrow inference has not decided. `ownedStage` is the caller's,
// which idr-rc knows as it grades.
export bool isBorrowed(func::FuncOp fn, unsigned index, bool ownedStage) {
  return ownedStage && index < fn.getNumArguments() && !isOwned(fn.getArgument(index).getType());
}

} // namespace idr::ownership
