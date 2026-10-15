// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values cells, static data and idr-lower's patterns are built from:
// the pointer type, constant words as LLVM writes them, the address
// of a component of a cell and the alignment it has there, the empty
// value of a counted component, and an unboxed sum's components.

#ifndef IDR_CONVERSION_WORDS_H
#define IDR_CONVERSION_WORDS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

mlir::Type ptrType(mlir::MLIRContext *ctx);

// The i64 and i32 constant `value`, as LLVM writes them: words of cells and
// static data, which the lowering writes on the LLVM dialect.
mlir::Value i64Constant(mlir::OpBuilder &b, mlir::Location loc, int64_t value);
mlir::Value i32Constant(mlir::OpBuilder &b, mlir::Location loc, int64_t value);

// The address of the byte `offset` of `cell`.
mlir::Value at(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, unsigned offset);

// The alignment a cell's start has: the runtime's word, for a cell it
// allocated, a static one, or a slot of a frame.
unsigned cellAlignment();

// The alignment of the component at `offset` from an address aligned to
// `base`: LLVM would otherwise take the alignment of the type from a data
// layout that the translation does not have yet.
unsigned alignAt(unsigned base, unsigned offset);

// The group word of a cell of the constructor `tag` of a grouped sum (one
// of more constructors than a header's tag holds): the group, the tag over
// IDRIS_RT_TAG_LIMIT, held as a small integer is, `group * 2 + 1`. The word
// is the cell's first object slot, and an odd word is one the runtime
// releases as it releases any small Integer: not at all.
int64_t groupWord(Tag tag);

// The first tag of the group the loaded group word `word`, an i64, names:
// the group times IDRIS_RT_TAG_LIMIT.
mlir::Value groupBase(mlir::OpBuilder &b, mlir::Location loc, mlir::Value word);

// The empty value of a counted component: a null pointer, or the word 0.
mlir::Value nullComponent(mlir::OpBuilder &b, mlir::Location loc, mlir::Type component);

// The components of the constructor `tag` of an unboxed sum laid out as
// `layout`, each field's components given by `fields` in order: the tag,
// where the sum has one, then every slot, zero in a slot the constructor
// uses none of, empty where the slot is counted, so that counting the sum
// counts each of its slots. LLVM constants, so the same components serve
// code and the initializer of a global.
llvm::SmallVector<mlir::Value> unboxedSum(mlir::OpBuilder &b, mlir::Location loc,
                                          const layout::SumLayout &layout, Tag tag,
                                          llvm::ArrayRef<mlir::ValueRange> fields);

// The components of field `index` of the constructor `tag` of `sum`, an
// unboxed sum laid out as `layout`.
llvm::SmallVector<mlir::Value> unboxedField(const layout::SumLayout &layout,
                                            mlir::ValueRange sum, Tag tag, unsigned index);

} // namespace idr::conversion

#endif // IDR_CONVERSION_WORDS_H
