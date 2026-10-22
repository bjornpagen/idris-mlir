// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A memref at runtime. Across a function's boundary and in a cell's field
// it is its components (Layouts::components): its cell, then the offset,
// each size and each stride its type leaves dynamic. Inside a function it
// is the descriptor upstream's memref ops read, built from the components
// where an op uses it: the allocated pointer is the cell, the aligned
// pointer the cell past its header, and the offset, sizes and strides are
// the components or the numbers the type fixes. The cell is the runtime's
// array cell, or a constant's static cell, whose header is in front of its
// data as every cell's is; so the element at index 0 is always right after
// the header, and the aligned pointer is never held. A view changes the
// offset, the sizes and the strides, never the cell.

#ifndef IDR_CONVERSION_ARRAYS_H
#define IDR_CONVERSION_ARRAYS_H

#include "idr/Conversion/Runtime.h"

#include "mlir/Conversion/LLVMCommon/TypeConverter.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Transforms/DialectConversion.h"
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

// Whether the ops on a memref of `type` that upstream vectorizes (the loads
// and stores of its elements, and linalg) stay for the passes after
// idr-lower: its elements are words, in the memory convert-to-llvm knows,
// the default.
bool leftToUpstream(mlir::MemRefType type);

// The descriptor of a value of `type` from its components.
Descriptor unpack(mlir::OpBuilder &b, mlir::Location loc, mlir::MemRefType type,
                  mlir::ValueRange components);

// The components of `descriptor` as a value of `type`: each field the type
// leaves dynamic, as an i64.
llvm::SmallVector<mlir::Value> pack(mlir::OpBuilder &b, mlir::Location loc, mlir::MemRefType type,
                                    const Descriptor &descriptor);

// The LLVM descriptor of type `llvmType` of a memref of `type`, built from
// its components: what upstream's memref ops read where they use it.
mlir::Value descriptorOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Type llvmType,
                         mlir::MemRefType type, mlir::ValueRange components);

// The components of a memref of `type` from its LLVM descriptor, where a
// value an upstream op made leaves the function or enters a cell: the
// allocated pointer, which is the cell, and each field the type leaves
// dynamic.
llvm::SmallVector<mlir::Value> componentsOf(mlir::OpBuilder &b, mlir::Location loc,
                                            mlir::MemRefType type, mlir::Value descriptor);

// Teaches the two converters of idr-lower each other's memrefs, so that
// the conversion moves a memref between them at each use: `components`,
// the converter of idr's ops, function boundaries and cells, takes a
// descriptor apart into components; `descriptors`, the converter of
// upstream's memref patterns, builds a descriptor from components, lays an
// element of ours out as its bytes, and puts mutable memory in address
// space 0. A legal op that holds a memref (a word's load or store, a linalg
// op over words) gets the memref cast from its descriptor, which meets the
// inverse cast in convert-to-llvm.
void addMemrefConversions(mlir::TypeConverter &components, mlir::LLVMTypeConverter &descriptors,
                          const Layouts &layouts);

// A field as an i64 value.
mlir::Value asWord(mlir::OpBuilder &b, mlir::Location loc, mlir::OpFoldResult field);

// The first element of an array cell, after its header and length: a
// memref descriptor's aligned pointer.
mlir::Value elementsOf(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell);

// An index operand (an `index`) as an i64, and a field as an `index`.
mlir::Value indexWord(mlir::OpBuilder &b, mlir::Location loc, mlir::Value index);
mlir::Value asIndex(mlir::OpBuilder &b, mlir::Location loc, mlir::OpFoldResult field);

// Each index of a converted operand group, one value each.
llvm::SmallVector<mlir::Value> indicesOf(llvm::ArrayRef<mlir::ValueRange> indices);

// The number of elements `sizes` cover, as an i64.
mlir::Value countOf(mlir::OpBuilder &b, mlir::Location loc,
                    llvm::ArrayRef<mlir::OpFoldResult> sizes);

// A new cell of `count` elements of `element`, from the runtime: fresh
// memory, which no other pointer reaches, its elements unwritten, which its
// maker writes before anything reads, releases or frees them.
mlir::Value newCell(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime, mlir::Value count,
                    const layout::Element &element);

// The patterns of the three movements a step makes in its buffers and of a
// fresh buffer's placed copy (Movements.cpp), which the array patterns add.
void populateMovementPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, const Layouts &layouts,
                              Runtime &runtime);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ARRAYS_H
