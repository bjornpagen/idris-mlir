// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A memref at runtime, as idr-lower holds it (Layouts::components): its
// cell, then the offset, each size and each stride its type leaves dynamic.
// The cell is the runtime's array cell, or a constant's static cell, whose
// header is in front of its data as every cell's is; so the element at
// index 0 is always right after the header, and the descriptor's aligned
// pointer, which upstream's memref ops read, is computed from the cell and
// never held. A view changes the offset, the sizes and the strides, never
// the cell.

#ifndef IDR_CONVERSION_ARRAYS_H
#define IDR_CONVERSION_ARRAYS_H

#include "idr/Conversion/Runtime.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// The fields of a memref's descriptor but its aligned pointer, which is
// elementsOf(cell). A field the type fixes is its IntegerAttr; any other is
// an i64 Value. An identity layout's offset is 0 and its strides are the
// row-major products of its sizes.
struct Descriptor {
  mlir::Value cell;
  mlir::OpFoldResult offset;
  llvm::SmallVector<mlir::OpFoldResult> sizes;
  llvm::SmallVector<mlir::OpFoldResult> strides;
};

// Whether a memref of `type` holds words: an element that is a builtin
// integer or float, which upstream's memref and linalg lowerings address
// and its vectorizer reads.
bool holdsWords(mlir::MemRefType type);

// The descriptor of a value of `type` from its components.
Descriptor unpack(mlir::OpBuilder &b, mlir::Location loc, mlir::MemRefType type,
                  mlir::ValueRange components);

// The components of `descriptor` as a value of `type`: each field the type
// leaves dynamic, as an i64.
llvm::SmallVector<mlir::Value> pack(mlir::OpBuilder &b, mlir::Location loc, mlir::MemRefType type,
                                    const Descriptor &descriptor);

// A field as an i64 value.
mlir::Value asWord(mlir::OpBuilder &b, mlir::Location loc, mlir::OpFoldResult field);

// The first element of an array cell, after its header and length: a
// memref descriptor's aligned pointer.
mlir::Value elementsOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

// The address of the element at `indices` (i64 values, one per dimension)
// of a memref whose elements are `stride` bytes apart.
mlir::Value elementAddress(mlir::OpBuilder &b, mlir::Location loc, const Descriptor &descriptor,
                           mlir::ValueRange indices, unsigned stride);

// An index operand (an `index`) as an i64, and a field as an `index`.
mlir::Value indexWord(mlir::OpBuilder &b, mlir::Location loc, mlir::Value index);
mlir::Value asIndex(mlir::OpBuilder &b, mlir::Location loc, mlir::OpFoldResult field);

// The number of elements `sizes` cover, as an i64.
mlir::Value countOf(mlir::OpBuilder &b, mlir::Location loc,
                    llvm::ArrayRef<mlir::OpFoldResult> sizes);

// The layout of an element of a buffer of `element`, or the refusal at `op`
// by the rule `layout`: a buffer of an element no cell can hold cannot be
// made.
mlir::FailureOr<layout::Element> elementOf(mlir::Operation *op, mlir::Type element,
                                           const Layouts &layouts);

// The value of the element at `address`: its slots, with no reference of
// its own.
llvm::SmallVector<mlir::Value> readElement(mlir::OpBuilder &b, mlir::Location loc,
                                           Runtime &runtime, mlir::Value address,
                                           const layout::Element &element);

// Writes `value`, of `type`, over the element at `address`: what the place
// held loses the reference it had, and `value` moves in with its own. An
// empty place releases nothing.
void writeElement(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                  const Layouts &layouts, mlir::Value address, const layout::Element &element,
                  mlir::Type type, mlir::ValueRange value);

// A memref of words as the legal ops that hold it read it: the descriptor
// convert-to-llvm reads for `type`, built over its components, cast to the
// memref by a cast that meets its inverse in convert-to-llvm. Null for a
// memref whose element is not a word, which no legal op holds.
mlir::Value toMemref(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime,
                     mlir::MemRefType type, mlir::ValueRange components);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ARRAYS_H
