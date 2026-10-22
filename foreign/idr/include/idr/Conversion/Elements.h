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
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr::conversion {

// The address of the element at `indices`, each an `index`, of a buffer of
// `type` whose components are `components` and whose element is laid out
// as `element`: every access to a buffer's element, of mutable memory or of
// a value array, a step's movements among them, addresses it here.
mlir::Value elementAddress(mlir::OpBuilder &b, mlir::Location loc, const Runtime &runtime,
                           mlir::MemRefType type, mlir::ValueRange components,
                           const layout::Element &element, mlir::ValueRange indices);

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

// What is known of a boxed element's box as it is moved out: unshared,
// where the array's claim covers its storage, of which a box is part, the
// lowering's layout; or known only at run time, since a copy of an array
// shares every box of the array it copies, and no idr value is the box for
// counting to split on.
enum class BoxSharing : std::uint8_t { Unshared, AtRunTime };

// What the type of `array`, at its grade, says of its boxes: unshared
// where it claims its own cells unshared, which covers its storage (or
// everything it reaches, which implies that).
BoxSharing boxSharingOf(mlir::Type array);

// The value of type `type` at `address`, moved out with the references the
// place held, the place left to be put back into (putIn): slots in place
// hold nothing to release; a boxed element's place keeps its box, emptied,
// for the value put back. A box a copy of the array shares keeps its value,
// which gains a reference of its own, and loses the place's, and the place
// takes an empty box of its own: so the box the place held is never freed
// only to make another of its size, and a copy's element never changes.
// Where the box is unshared by `sharing`, nothing is tested.
llvm::SmallVector<mlir::Value> takeOut(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                                       const Layouts &layouts, mlir::Value address,
                                       const layout::Element &element, mlir::Type type,
                                       BoxSharing sharing);

// Puts `value` back in the place a take left at `address`: into its slots,
// or into the box the take left there.
void putIn(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime, mlir::Value address,
           const layout::Element &element, mlir::ValueRange value);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ELEMENTS_H
