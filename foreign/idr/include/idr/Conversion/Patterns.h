// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower: the conversion patterns of each idr op and type,
// with the layouts and the runtime they lower with.

#ifndef IDR_CONVERSION_PATTERNS_H
#define IDR_CONVERSION_PATTERNS_H

#include "idr/IR/Layout.h"
#include "idr/Conversion/Fields.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// The ops that count references: calls of the runtime, which LTO inlines.
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime, const Fields &fields);

// Bigs and naturals, whose small case is inline.
void populateBigPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime);

// The cells memrefs live in, allocated or constant, and the arrays a world
// orders. `globals` holds every memref.global of the module by name.
void populateArrayPatterns(
    mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
    const Layouts &layouts, Runtime &runtime,
    const llvm::DenseMap<mlir::StringAttr, mlir::memref::GlobalOp> &globals);

// The ops on buffers: their extents, views, copies, and the elements of
// ours they hold.
void populateMemrefPatterns(mlir::RewritePatternSet &patterns,
                            const mlir::TypeConverter &converter, const Layouts &layouts,
                            Runtime &runtime);

// A machine word in a buffer of bytes.
void populateBufferPatterns(mlir::RewritePatternSet &patterns,
                            const mlir::TypeConverter &converter, const Layouts &layouts,
                            Runtime &runtime);

// The string builders over lists, and the output of such a list.
void populateStringPatterns(mlir::RewritePatternSet &patterns,
                            const mlir::TypeConverter &converter, const Layouts &layouts,
                            Runtime &runtime);

// Cells and unboxed sums, and the changes of grade and kind that have no
// runtime form.
void populateCellPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime);

// Crashes, forged worlds, loops that need not end, and the scalar
// operations whose meaning is more than arith's.
void populateScalarPatterns(mlir::RewritePatternSet &patterns,
                            const mlir::TypeConverter &converter, const Layouts &layouts,
                            Runtime &runtime);

// The ops that call the runtime, and the comparisons whose runtime
// function orders its operands.
void populateRuntimeCallPatterns(mlir::RewritePatternSet &patterns,
                                 const mlir::TypeConverter &converter, const Layouts &layouts,
                                 Runtime &runtime);

// The guards.
void populateCheckPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime);

// A label of a memo sum as a force calls it: its tag, the label's
// function by its mangled name, and for each capture whether that function
// takes it owned (idr-rc may make the function borrow a parameter).
struct MemoLabel {
  unsigned tag;
  mlir::FlatSymbolRefAttr callee;
  llvm::SmallVector<bool> owned;
};

// The memo sums the module's forces read, each with its labels. Read once
// the functions have their mangled names and before any is converted: the
// conversion rewrites each label function's signature, and the grades in
// it, when it meets the function. A force of a value that is not a memo
// cell, or a label no function of its captures answers, is an internal
// error, reported here.
using Memos = llvm::DenseMap<DataType, llvm::SmallVector<MemoLabel>>;
mlir::FailureOr<Memos> readMemos(mlir::ModuleOp module, mlir::SymbolTable &symbols);

// The force of a memo cell. No suspension reaches the lowering:
// idr-defunctionalize has made each a constructor of a memo sum.
void populateLazyPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime, const Memos &memos);

} // namespace idr::conversion

#endif // IDR_CONVERSION_PATTERNS_H
