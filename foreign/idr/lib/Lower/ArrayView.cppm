// idr.lower:arrayView: an array of words as the memref convert-to-llvm
// addresses: a descriptor over the array's cell.
module;
// The runtime's C ABI: an array's cell is its header and length, then the
// elements.
#include "idris_rt.h"

export module idr.lower:arrayView;

import idr.mlir;

import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

// The first element of the cell, after the header and the length.
Value elementsOf(OpBuilder &b, Location loc, Value cell) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(sizeof(idris_rt_array))},
                             LLVM::GEPNoWrapFlags::inbounds);
}

// The memref view of an array of words: the descriptor convert-to-llvm
// reads for a memref of `view`'s type, built over the cell and its length.
// Phase 2 gives it to every legal op that still holds the array.
//
// The descriptor's allocated pointer is the cell, which only the runtime
// frees, through the count; its aligned pointer the first element; its
// offset 0, its size the length, its stride 1. The cast to the memref
// meets its inverse in convert-to-llvm.
export Value arrayView(OpBuilder &b, Location loc, Runtime &runtime, MemRefType view, Value cell,
                       Value length) {
  auto descriptor = MemRefDescriptor::poison(b, loc, runtime.llvmTypeConverter().convertType(view));
  descriptor.setAllocatedPtr(b, loc, cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, cell));
  descriptor.setConstantOffset(b, loc, 0);
  descriptor.setSize(b, loc, 0, length);
  descriptor.setConstantStride(b, loc, 0, 1);
  return UnrealizedConversionCastOp::create(b, loc, view, Value(descriptor)).getResult(0);
}

} // namespace idr::lower
