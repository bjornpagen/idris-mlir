// idr.io.write_bytes and idr.io.read_bytes: IO of the bytes of a buffer.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

LogicalResult WriteBytesOp::verify() { return ops::verifyByteBuffer(*this); }
LogicalResult ReadBytesOp::verify() { return ops::verifyByteBuffer(*this); }

namespace {

// The range is what the program computed, so it may lie outside the
// buffer; the runtime checks it in the function the op calls, and crashes
// with this message.
constexpr StringRef outsideBuffer = "a byte range outside the buffer";

} // namespace

std::optional<StringRef> WriteBytesOp::getCrashCause() { return outsideBuffer; }
std::optional<StringRef> ReadBytesOp::getCrashCause() { return outsideBuffer; }

void WriteBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
void ReadBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(getCrashCause(), Value(), effects);
}
