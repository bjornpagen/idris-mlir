// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower: the conversion patterns of each idr op and type,
// with the layouts and the runtime they lower with. A runtime holds no
// state, so one serves every function lowered at once.

#ifndef IDR_CONVERSION_PATTERNS_H
#define IDR_CONVERSION_PATTERNS_H

#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/DenseMap.h"

namespace idr::conversion {

// The counting ops: a count by the entry of each word's kind, a take of a
// value its type proves unshared with no test, a drop of one that frees its
// own cells with no count read, the one test of sharing where its type
// proves nothing, the frees of tokens, and the null token.
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

// The big and natural ops that are no call of one runtime function: a
// natural made an extent, which ends the run as out of memory where the
// natural is past every allocation, and a numeral made a natural or made of
// one, by the numeral's layout.
void populateBigPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime);

// The cells memrefs live in, allocated or constant, and the arrays of
// mutable memory: their reads, writes and updates in place; and the
// movements a step of a generating op makes in its buffers (a take, a copy,
// a place) and the copy placed in a buffer allocated for it. `arrays` holds
// every memref.global of the program by name, read as a constant array.
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

// The counted cells, each made by its source and written by its init; and
// the data values, built, read and taken apart by their layouts.
void populateCellPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime);

// The places written once through a destination: a hole of a cell, and the
// slots of a row's answers.
void populateDestinationPatterns(mlir::RewritePatternSet &patterns,
                                 const mlir::TypeConverter &converter, const Layouts &layouts,
                                 Runtime &runtime);

// The ends of a run, the IO a trusted library runs for a value, and the
// ops of inline arithmetic.
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
