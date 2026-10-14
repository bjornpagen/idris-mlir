// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values cells, static data and idr-lower's patterns are built from:
// the pointer type, constant words as LLVM writes them, the address
// of a component of a cell and the alignment it has there, and the empty
// value of a counted component.

#ifndef IDR_CONVERSION_WORDS_H
#define IDR_CONVERSION_WORDS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"

namespace idr::conversion {

mlir::Type ptrType(mlir::MLIRContext *ctx);

// The i64 and i32 constant `value`, as LLVM writes them: words of cells and
// static data, which the lowering writes on the LLVM dialect.
mlir::Value i64Constant(mlir::OpBuilder &b, mlir::Location loc, int64_t value);
mlir::Value i32Constant(mlir::OpBuilder &b, mlir::Location loc, int64_t value);

// The address of the byte `offset` of `cell`.
mlir::Value at(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, unsigned offset);

// The alignment of the component at `offset` in a cell, which is
// word-aligned: LLVM would otherwise take the alignment of the type from a
// data layout that the translation does not have yet.
unsigned alignAt(unsigned offset);

// The empty value of a counted component: a null pointer, or the word 0.
mlir::Value nullComponent(mlir::OpBuilder &b, mlir::Location loc, mlir::Type component);

} // namespace idr::conversion

#endif // IDR_CONVERSION_WORDS_H
