// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The place of an element of an array (Elements.h): its address in its
// buffer; its slots in place, or one counted pointer to a cell of its own;
// its value read with no reference of its own, written over what it held,
// put where nothing is held, and moved out with the place's references,
// the place left to be put back into.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/Words.h"

#include "mlir/Conversion/LLVMCommon/Pattern.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;

namespace idr::conversion {

unsigned elementAlignment(const layout::Element &element) {
  return alignAt(cellAlignment(), element.stride);
}

namespace {

// The memref type upstream's getStridedElementPtr addresses an element of
// `type` through, `element` its layout: `type` itself, whose element the
// descriptors converter gives as what an element holds (a word as itself,
// an element of ours as its bytes), so the address steps by the element's
// stride. An element that is itself an array is what the converter cannot
// give: it gives an array as the descriptor a value of it is in a
// function, while an element holds its components (Layouts::element), two
// runtime forms of one type that no conversion of the type alone tells
// apart. Only mutable memory holds an array (a value array holds no shaped
// element), and its layout is the identity of rank 1 at most, whose strides
// its type fixes: it is addressed as a view of the same cell's bytes, each
// stride scaled by the element's.
MemRefType addressedAs(MemRefType type, const layout::Element &element) {
  if (!isa<ShapedType>(type.getElementType()))
    return type;
  auto [strides, offset] = type.getStridesAndOffset();
  auto scaled = [&](int64_t elements) { return elements * static_cast<int64_t>(element.stride); };
  MLIRContext *ctx = type.getContext();
  return MemRefType::get(
      type.getShape(), IntegerType::get(ctx, 8),
      StridedLayoutAttr::get(ctx, scaled(offset), llvm::map_to_vector(strides, scaled)),
      type.getMemorySpace());
}

// A boxed element's cell, the one pointer the place holds.
Value boxOf(OpBuilder &b, Location loc, Runtime &runtime, Value address,
            const layout::Element &element) {
  return runtime.load(b, loc, address, elementAlignment(element), element.slots).front();
}

} // namespace

// Upstream's strided address over the buffer's descriptor, each index a
// word.
Value elementAddress(OpBuilder &b, Location loc, const Runtime &runtime, MemRefType type,
                     ValueRange components, const layout::Element &element,
                     ValueRange indices) {
  SmallVector<Value> words =
      llvm::map_to_vector(indices, [&](Value index) { return indexWord(b, loc, index); });
  const LLVMTypeConverter &descriptors = runtime.llvmTypeConverter();
  Value descriptor = descriptorOf(b, loc, descriptors.convertType(type), type, components);
  return LLVM::getStridedElementPtr(b, loc, descriptors, addressedAs(type, element), descriptor,
                                    words, LLVM::GEPNoWrapFlags::inbounds);
}

SmallVector<Value> readElement(OpBuilder &b, Location loc, Runtime &runtime, Value address,
                               const layout::Element &element) {
  if (!element.boxed)
    return runtime.load(b, loc, address, elementAlignment(element), element.slots);
  return runtime.load(b, loc, boxOf(b, loc, runtime, address, element), cellAlignment(),
                      element.boxed->fields.front());
}

void placeElement(OpBuilder &b, Location loc, Runtime &runtime, Value address,
                  const layout::Element &element, ValueRange value) {
  if (!element.boxed) {
    runtime.store(b, loc, address, elementAlignment(element), element.slots, value);
    return;
  }
  Value cell = runtime.allocate(b, loc, *element.boxed);
  runtime.store(b, loc, cell, cellAlignment(), element.boxed->fields.front(), value);
  runtime.store(b, loc, address, elementAlignment(element), element.slots, cell);
}

void writeElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                  Value address, const layout::Element &element, Type type, ValueRange value) {
  if (element.boxed) {
    runtime.dec(b, loc, layout::Word::Cell, boxOf(b, loc, runtime, address, element));
  } else {
    SmallVector<layout::Component> components = layouts.components(type);
    // An element of words holds nothing to release, which its layout says:
    // its place is not read.
    if (llvm::any_of(components,
                     [](const layout::Component &c) { return c.word != layout::Word::Uncounted; }))
      runtime.dec(b, loc, components, readElement(b, loc, runtime, address, element));
  }
  placeElement(b, loc, runtime, address, element, value);
}

BoxSharing boxSharingOf(Type array) {
  return claims(array, Unique::Deep) ? BoxSharing::Unshared : BoxSharing::AtRunTime;
}

SmallVector<Value> takeOut(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                           Value address, const layout::Element &element, Type type,
                           BoxSharing sharing) {
  if (!element.boxed)
    return readElement(b, loc, runtime, address, element);
  Value cell = boxOf(b, loc, runtime, address, element);
  SmallVector<Value> value =
      runtime.load(b, loc, cell, cellAlignment(), element.boxed->fields.front());
  if (sharing == BoxSharing::Unshared)
    return value;
  // Whether a copy of the array shares the box is known only here, at run
  // time. Held by the place alone, the box stays for the value put back.
  auto alone = scf::IfOp::create(b, loc, runtime.isUnique(b, loc, cell),
                                 /*withElseRegion=*/true);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPoint(alone.elseBlock()->getTerminator());
  runtime.inc(b, loc, layouts.components(type), value);
  runtime.dec(b, loc, layout::Word::Cell, cell);
  runtime.store(b, loc, address, elementAlignment(element), element.slots,
                runtime.allocate(b, loc, *element.boxed));
  return value;
}

void putIn(OpBuilder &b, Location loc, Runtime &runtime, Value address,
           const layout::Element &element, ValueRange value) {
  if (!element.boxed) {
    placeElement(b, loc, runtime, address, element, value);
    return;
  }
  runtime.store(b, loc, boxOf(b, loc, runtime, address, element), cellAlignment(),
                element.boxed->fields.front(), value);
}

} // namespace idr::conversion
