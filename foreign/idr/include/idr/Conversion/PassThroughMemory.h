// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions on a tail call whose result does not fit the return
// registers write it through a pointer instead, each rewritten on its own
// from the plan.

#ifndef IDR_CONVERSION_PASSTHROUGHMEMORY_H
#define IDR_CONVERSION_PASSTHROUGHMEMORY_H

#include "idr/Conversion/TailCallPlan.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// `fn` takes a pointer to write its result to, first, `noalias`, and
// returns nothing; the pointer.
mlir::Value takeResultPointer(mlir::LLVM::LLVMFuncOp fn, mlir::RewriterBase &rewriter);

// Each of `calls`, calls in `fn` of functions whose result goes through
// memory, in the callee's new type. A call in `tailCalls`, right before the
// return of its result, passes on `out`, the pointer `fn` itself got (it
// returns the same type, so it goes through memory too), and the return
// after it returns nothing; any other passes a slot of `fn`'s frame and
// reads the result from it. `tailCalls` follows the calls as they are made
// again.
void callThroughMemory(mlir::LLVM::LLVMFuncOp fn,
                       llvm::ArrayRef<TailCallPlan::ThroughMemory> calls,
                       llvm::SmallVectorImpl<mlir::LLVM::CallOp> &tailCalls, mlir::Value out,
                       mlir::RewriterBase &rewriter);

// Every return of `fn` that still returns a value writes it through `out`
// and returns nothing.
void storeResults(mlir::LLVM::LLVMFuncOp fn, mlir::Value out, mlir::RewriterBase &rewriter);

} // namespace idr::conversion

#endif // IDR_CONVERSION_PASSTHROUGHMEMORY_H
