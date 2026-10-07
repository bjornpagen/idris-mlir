// The buffer ops: a machine word at a byte offset, a copy, a string written
// or read. The range is what the program computed, so it may lie outside
// the buffer; the runtime checks it in idris_rt_buffer_at and crashes with
// the same message a byte transfer uses.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

namespace {

constexpr StringRef outsideBuffer = "a byte range outside the buffer";

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

std::optional<StringRef> BufferLoadOp::getCrashCause() { return outsideBuffer; }
std::optional<StringRef> BufferStoreOp::getCrashCause() { return outsideBuffer; }
std::optional<StringRef> BufferCopyOp::getCrashCause() { return outsideBuffer; }
std::optional<StringRef> BufferSetStringOp::getCrashCause() { return outsideBuffer; }
std::optional<StringRef> BufferGetStringOp::getCrashCause() { return outsideBuffer; }

void BufferLoadOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void BufferStoreOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void BufferCopyOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void BufferSetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void BufferGetStringOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), getStr(), effects);
}
