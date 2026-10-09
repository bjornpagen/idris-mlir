// idr.ownership:useof: what each use of a reference does with it.
export module idr.ownership:useof;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// What a use does with a reference in the owned stage: consumes one, or
// only needs the value to be alive. Its op declares which (idr::consumes):
// returns, scf's yields, a call's owned parameters and the operands ODS
// names beside each idr op consume; everything else borrows, the closure an
// apply calls included. A force is placement's: idr-rc gives it its cell
// owned where the cell dies, and there it takes the cell over; anywhere
// else it reads a view.
export enum class Use { Consume, Borrow };

export Use useOf(OpOperand &operand) {
  if (isa<ForceOp>(operand.getOwner()))
    return isOwned(operand.get().getType()) ? Use::Consume : Use::Borrow;
  return consumes(operand) ? Use::Consume : Use::Borrow;
}

} // namespace idr::ownership
