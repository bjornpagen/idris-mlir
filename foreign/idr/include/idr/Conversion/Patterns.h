// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower: the conversion patterns of each idr op and type,
// with the layouts and the runtime they lower with.

#ifndef IDR_CONVERSION_PATTERNS_H
#define IDR_CONVERSION_PATTERNS_H

#include "idr/IR/Layout.h"
#include "idr/Conversion/Fields.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"

namespace idr::conversion {

// The ops that count references: calls of the runtime, which LTO inlines.
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime, const Fields &fields);

// Bigs and naturals, whose small case is inline.
void populateBigPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime);

// Arrays: their cells, lengths and elements.
void populateArrayPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                           const Layouts &layouts, Runtime &runtime);

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

// The force of a memo cell. No suspension reaches the lowering:
// idr-defunctionalize has made each a constructor of a memo sum.
void populateLazyPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime);

} // namespace idr::conversion

#endif // IDR_CONVERSION_PATTERNS_H
