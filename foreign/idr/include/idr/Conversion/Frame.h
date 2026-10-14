// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What of a function may point into its frame, which a call that may reach
// it keeps from being a tail call.

#ifndef IDR_CONVERSION_FRAME_H
#define IDR_CONVERSION_FRAME_H

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "llvm/ADT/DenseSet.h"

namespace idr::conversion {

// What of a function may point into its frame: its slots (llvm.alloca, the
// cells idr-stack put there), what is computed from them, and what is read
// through them, since a slot may hold a pointer to another. A pointer into
// the frame may also have left it through memory, written somewhere that is
// not the frame: then any pointer a call takes may lead back to the frame.
// What a call does with a pointer it takes is idr-stack's to know: it puts on
// the stack only a cell that no callee keeps.
struct Frame {
  llvm::DenseSet<mlir::Value> bound;
  bool leaked = false;

  // Whether a value of `type` may hold a pointer: a pointer, or an
  // aggregate of anything that may (an array's view).
  static bool mayPoint(mlir::Type type);

  explicit Frame(mlir::LLVM::LLVMFuncOp fn);

  // Whether `call` may reach the frame through what it takes.
  bool reachedBy(mlir::LLVM::CallOp call) const;
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_FRAME_H
