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
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseMap.h"

namespace idr::conversion {

// The ops that count references, and the take of a cell: calls of the
// runtime, which LTO inlines.
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

// The big op that is no call of one runtime function: a natural made an
// extent, which crashes at the op where the natural is past every extent.
void populateBigPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime);

// The cells memrefs live in, allocated or constant, and the arrays a world
// orders: their reads, writes and updates in place. `arrays` holds every
// memref.global of the program by name, read as a constant array.
void populateArrayPatterns(mlir::RewritePatternSet &patterns,
                           const mlir::TypeConverter &converter, const Layouts &layouts,
                           Runtime &runtime,
                           const llvm::DenseMap<mlir::StringAttr, ConstantArray> &arrays);

// The ops on buffers whose meaning is the runtime's: the elements of ours
// they hold, and the copies upstream's memcpy does not cover.
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

// The cells, each made by its producer and written by its init, and the
// sums held in place, built and unpacked; `fields` says which fields a
// recycled cell holds already.
void populateCellPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime, const Fields &fields);

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

// The writes of a memo cell's state: running, and forced with its value.
void populateMemoPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime);

} // namespace idr::conversion

#endif // IDR_CONVERSION_PATTERNS_H
