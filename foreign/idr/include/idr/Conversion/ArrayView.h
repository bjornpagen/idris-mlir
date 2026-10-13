// An array of words as the memref convert-to-llvm addresses: a descriptor
// over the array's cell.

#ifndef IDR_CONVERSION_ARRAYVIEW_H
#define IDR_CONVERSION_ARRAYVIEW_H

#include "idr/Conversion/Runtime.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"

namespace idr::conversion {

// The first element of the cell, after the header and the length.
mlir::Value elementsOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

// The memref view of an array of words: the descriptor convert-to-llvm
// reads for a memref of `view`'s type, built over the array's components,
// its cell and then its size in each dimension (none for an IORef's).
// Phase 2 gives it to every legal op that still holds the array.
mlir::Value arrayView(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                      mlir::MemRefType view, mlir::ValueRange array);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ARRAYVIEW_H
