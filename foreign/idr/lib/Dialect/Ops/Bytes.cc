// idr.io.write_bytes and idr.io.read_bytes: IO of the bytes of a buffer. The
// range is what the program computed; idr.check.range checks it before the
// op.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

LogicalResult WriteBytesOp::verify() { return ops::verifyByteBuffer(*this); }
LogicalResult ReadBytesOp::verify() { return ops::verifyByteBuffer(*this); }

void WriteBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
void ReadBytesOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  ops::ioEffects(Value(), effects);
}
