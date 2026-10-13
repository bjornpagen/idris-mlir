// Whether a call on the LLVM dialect is in tail position, as idr-tail-calls
// decides it: by what the path from the call to a return decides alone.

#ifndef IDR_CONVERSION_TAILPOSITION_H
#define IDR_CONVERSION_TAILPOSITION_H

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

namespace idr::conversion {

// Whether `call`, in `fn`, is in tail position: the path from it, which every
// op on it decides alone, returns the call's result unchanged, or returns
// nothing after a call that returns nothing. Every op on the way only
// computes, so returning right after the call loses nothing. It reads the
// function and writes nothing, so functions are asked in parallel.
bool inTailPosition(mlir::LLVM::CallOp call, mlir::LLVM::LLVMFuncOp fn);

} // namespace idr::conversion

#endif // IDR_CONVERSION_TAILPOSITION_H
