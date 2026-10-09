// The buffer ops: a machine word at a byte offset, a copy, a string written
// or read. The range is what the program computed, so it may lie outside
// the buffer; idr.check.range checks it before the op, which then reads and
// writes only inside it.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

namespace {

LogicalResult verifyBuffer(Operation *op, Value buffer) {
  auto array = dyn_cast<MemRefType>(unrestricted(buffer.getType()));
  if (!array || !array.getElementType().isInteger(8))
    return op->emitOpError("operates on a buffer of i8, not ") << buffer.getType();
  return success();
}

} // namespace

LogicalResult BufferLoadOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferStoreOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferSetStringOp::verify() { return verifyBuffer(*this, getBuffer()); }
LogicalResult BufferGetStringOp::verify() { return verifyBuffer(*this, getBuffer()); }

LogicalResult BufferCopyOp::verify() {
  if (failed(verifyBuffer(*this, getSrc())))
    return failure();
  return verifyBuffer(*this, getDst());
}

void BufferLoadOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void BufferStoreOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void BufferCopyOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void BufferSetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void BufferGetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getStr(), effects);
}
