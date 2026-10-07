// idr.ownership:useof: what each use of a reference does with it.
export module idr.ownership:useof;

import idr.mlir;
import idr.dialect;

import :borrowed;
import :callee;

using namespace mlir;

namespace idr::ownership {

// What a use does with a reference: consumes one, or only needs the value to
// be alive. Returns, yields, constructors, closures, takes, reuses, decs,
// arguments of owned parameters and the arguments of an apply consume;
// everything else borrows, the closure an apply calls included.
export enum class Use { Consume, Borrow };

export Use useOf(OpOperand &operand, SymbolTableCollection &symbols) {
  Operation *op = operand.getOwner();
  if (auto call = dyn_cast<func::CallOp>(op)) {
    func::FuncOp fn = callee(call, symbols);
    return fn && isBorrowed(fn, operand.getOperandNumber()) ? Use::Borrow : Use::Consume;
  }
  // The callee is operand 0. It may already be graded, so it is not
  // getCallee(), which casts the value to the closure type.
  if (isa<ApplyOp>(op))
    return operand.getOperandNumber() == 0 ? Use::Borrow : Use::Consume;
  // A linear value moves into its one use and out of it again, with its
  // reference; so does a natural into the Integer it is, and a value
  // written to a destination into the cell.
  if (isa<func::ReturnOp, YieldOp, ConOp, ClosureOp, SuspendOp, ReuseOp, TakeOp, DropOp, LinEnterOp,
          LinUseOp, ShareOp, NatToBigOp, DestWriteOp, scf::ConditionOp, scf::YieldOp,
          scf::WhileOp>(op))
    return Use::Consume;
  // An element moves into the array's cell; the array itself is read. The
  // fill of a generated array moves in likewise, and a fold's init into
  // its body as the first accumulator.
  if (auto make = dyn_cast<ArrayNewOp>(op))
    return operand.get() == make.getFill() ? Use::Consume : Use::Borrow;
  if (auto set = dyn_cast<ArraySetOp>(op))
    return operand.get() == set.getValue() ? Use::Consume : Use::Borrow;
  if (auto generate = dyn_cast<ArrayGenerateOp>(op))
    return operand.get() == generate.getFill() ? Use::Consume : Use::Borrow;
  if (auto fold = dyn_cast<ArrayFoldOp>(op))
    return operand.get() == fold.getInit() ? Use::Consume : Use::Borrow;
  return Use::Borrow;
}

} // namespace idr::ownership
