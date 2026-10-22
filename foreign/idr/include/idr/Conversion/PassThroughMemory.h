// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions whose result does not fit the return registers write it
// through a pointer instead, each rewritten on its own, a fact of its
// result's type alone.

#ifndef IDR_CONVERSION_PASSTHROUGHMEMORY_H
#define IDR_CONVERSION_PASSTHROUGHMEMORY_H

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// `fn` takes a pointer to write its result to, first, `noalias`, and
// returns nothing; the pointer.
mlir::Value takeResultPointer(mlir::LLVM::LLVMFuncOp fn, mlir::RewriterBase &rewriter);

// Each of `tailCalls`, calls right before the return of their result in a
// function that took `out` to write its result to, of functions that take
// such a pointer too, passes on `out` instead, and the return after it
// returns nothing. `tailCalls` follows the calls as they are made again.
void passOnPointer(llvm::SmallVectorImpl<mlir::LLVM::CallOp> &tailCalls, mlir::Value out,
                   mlir::RewriterBase &rewriter);

// Each of `calls`, calls in `fn` of functions whose result goes through
// memory, passes a slot of `fn`'s frame and reads the result from it.
void callThroughSlots(mlir::LLVM::LLVMFuncOp fn, llvm::ArrayRef<mlir::LLVM::CallOp> calls,
                      mlir::RewriterBase &rewriter);

// Every return of `fn` that still returns a value writes it through `out`
// and returns nothing.
void storeResults(mlir::LLVM::LLVMFuncOp fn, mlir::Value out, mlir::RewriterBase &rewriter);

} // namespace idr::conversion

#endif // IDR_CONVERSION_PASSTHROUGHMEMORY_H
