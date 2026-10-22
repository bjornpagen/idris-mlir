// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The place of an element of an array, at its address: in place, its slots
// at their offsets from the element's start, laid out as a cell's fields
// are (Layouts::element); or, where the array's header cannot describe it,
// boxed, one counted pointer to a cell of its own that holds the value as a
// box of one field holds it.

#ifndef IDR_CONVERSION_ELEMENTS_H
#define IDR_CONVERSION_ELEMENTS_H

#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// The alignment of an element's start: the cell's elements start at a word,
// and each is the stride after the one before.
unsigned elementAlignment(const layout::Element &element);

// The value of the element at `address`: its slots, or its cell's field,
// with no reference of its own.
llvm::SmallVector<mlir::Value> readElement(mlir::OpBuilder &b, mlir::Location loc,
                                           Runtime &runtime, mlir::Value address,
                                           const layout::Element &element);

// Puts `value` in the place at `address`, which holds nothing to release:
// it moves in with its references, a boxed element in a new cell of its own.
void placeElement(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime, mlir::Value address,
                  const layout::Element &element, mlir::ValueRange value);

// Writes `value`, of `type`, over the element at `address`: what the place
// held loses the reference it had, and `value` moves in with its own.
void writeElement(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                  const Layouts &layouts, mlir::Value address, const layout::Element &element,
                  mlir::Type type, mlir::ValueRange value);

// An element moved out of its place to be rebuilt and moved back: its
// value, with the references the place held, and, for a boxed element, the
// box the rebuilt value goes back into.
struct Taken {
  llvm::SmallVector<mlir::Value> value;
  mlir::Value box;
};

// The value of type `type` at `address`, moved out with the references the
// place held, which then holds nothing to release until a value is put
// back. A boxed element's box is kept for the value put back where the
// place alone held it, and a new one is made where a copy of the array
// shares it, which keeps its value and loses the place's reference: so the
// box the place held is never freed only to make another of its size.
Taken takeElement(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                  const Layouts &layouts, mlir::Value address, const layout::Element &element,
                  mlir::Type type);

// Puts `value` back in the place `taken` left at `address`.
void putBack(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime, mlir::Value address,
             const layout::Element &element, const Taken &taken, mlir::ValueRange value);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ELEMENTS_H
