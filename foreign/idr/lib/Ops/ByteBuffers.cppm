// idr.ops:bytebuffers: the buffer of a byte transfer (idr.io.write_bytes,
// idr.io.read_bytes).
export module idr.ops:bytebuffers;

import idr.mlir;
import idr.dialect;

export namespace idr::ops {

// The buffer of a byte transfer holds bytes.
template <typename OpT> mlir::LogicalResult verifyByteBuffer(OpT op) {
  auto array = mlir::cast<mlir::MemRefType>(idr::unrestricted(op.getBuffer().getType()));
  if (!array.getElementType().isInteger(8))
    return op.emitOpError("transfers bytes, so its buffer must hold i8, not ")
           << array.getElementType();
  return mlir::success();
}

} // namespace idr::ops
