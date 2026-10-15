// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a call on the LLVM dialect is in tail position, as idr-tail-calls
// decides it: by what the path from the call to a return decides alone.

#ifndef IDR_CONVERSION_TAILPOSITION_H
#define IDR_CONVERSION_TAILPOSITION_H

#include "mlir/Analysis/Liveness.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

namespace idr::conversion {

// The paths from the calls of one function to its returns. It reads the
// function and writes nothing, so functions are asked in parallel.
class TailPaths {
public:
  explicit TailPaths(mlir::LLVM::LLVMFuncOp fn)
      : result(fn.getFunctionType().getReturnType()), liveness(fn) {}

  // Whether `call`, in the function, is in tail position: the path from it,
  // which every op on it decides alone, returns the call's result
  // unchanged, or returns nothing after a call that returns nothing. Every
  // op on the way only computes, so returning right after the call loses
  // nothing.
  bool inTailPosition(mlir::LLVM::CallOp call) const;

private:
  // The function's result type, void when it returns nothing.
  mlir::Type result;
  // What a block's future reads of the path: the values live into it.
  mlir::Liveness liveness;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_TAILPOSITION_H
