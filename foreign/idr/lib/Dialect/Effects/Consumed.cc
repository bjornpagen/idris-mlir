// Where a use takes over the reference its value holds, as the op that
// uses it declares, and what taking it over is to every other pass.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::consumes(OpOperand &operand) {
  Operation *op = operand.getOwner();
  if (auto consuming = dyn_cast<ConsumingOpInterface>(op))
    return consuming.consumesOperand(operand.getOperandNumber());
  // A function's results, and what a loop carries into its next iteration
  // or out of it, move on with their references.
  if (isa<func::ReturnOp, scf::YieldOp, scf::WhileOp>(op))
    return true;
  if (auto condition = dyn_cast<scf::ConditionOp>(op))
    return &operand != &condition.getConditionMutable();
  // A call takes an argument over unless the callee borrows the parameter:
  // a borrowed one is a view, plain, where one the callee takes is owned.
  // Before idr-rc grades the signatures no parameter is owned yet, and
  // idr-rc's reuse insertion, which runs then, takes every call to consume
  // its arguments itself.
  if (auto call = dyn_cast<func::CallOp>(op)) {
    auto fn = idr::lookupSymbol<func::FuncOp>(call, call.getCalleeAttr().getAttr());
    unsigned index = operand.getOperandNumber();
    return !fn || index >= fn.getNumArguments() || isOwned(fn.getArgumentTypes()[index]);
  }
  return false;
}

// A Free on the reference resource is what keeps an op that takes an owned
// value over from being dropped as dead or merged with another: before
// idr-rc no value is owned, and the op is as free to drop as its other
// effects let it be.
void idr::consumedEffects(
    Operation *op, SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  for (OpOperand &operand : op->getOpOperands())
    if (isOwned(operand.get().getType()) && consumes(operand))
      effects.emplace_back(MemoryEffects::Free::get(), &operand, ReferenceResource::get());
}
