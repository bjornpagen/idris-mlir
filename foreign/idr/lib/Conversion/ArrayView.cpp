// An array of words as the memref convert-to-llvm addresses.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/ArrayView.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Conversion/LLVMCommon/MemRefBuilder.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"

// The runtime's C ABI: an array's cell is its header and length, then the
// elements.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

Value elementsOf(OpBuilder &b, Location loc, Value cell) {
  return LLVM::GEPOp::create(b, loc, ptrType(b.getContext()), b.getI8Type(), cell,
                             ArrayRef<LLVM::GEPArg>{static_cast<int32_t>(sizeof(idris_rt_array))},
                             LLVM::GEPNoWrapFlags::inbounds);
}

// The descriptor's allocated pointer is the cell, which only the runtime
// frees, through the count; its aligned pointer the first element; its
// offset 0, each size the array's, each stride 1. The cast to the memref
// meets its inverse in convert-to-llvm.
Value arrayView(OpBuilder &b, Location loc, Runtime &runtime, MemRefType view, ValueRange array) {
  Value cell = array.front();
  auto descriptor = MemRefDescriptor::poison(b, loc, runtime.llvmTypeConverter().convertType(view));
  descriptor.setAllocatedPtr(b, loc, cell);
  descriptor.setAlignedPtr(b, loc, elementsOf(b, loc, cell));
  descriptor.setConstantOffset(b, loc, 0);
  for (auto [dim, size] : llvm::enumerate(array.drop_front())) {
    descriptor.setSize(b, loc, static_cast<unsigned>(dim), size);
    descriptor.setConstantStride(b, loc, static_cast<unsigned>(dim), 1);
  }
  return UnrealizedConversionCastOp::create(b, loc, view, Value(descriptor)).getResult(0);
}

} // namespace idr::conversion
