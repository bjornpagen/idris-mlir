// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The place of an element of an array (Elements.h): its slots in place, or
// one counted pointer to a cell of its own; its value read with no
// reference of its own, written over what it held, put where nothing is
// held, and moved out with the place's references to be put back.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::conversion {

unsigned elementAlignment(const layout::Element &element) {
  return alignAt(cellAlignment(), element.stride);
}

namespace {

// A boxed element's cell, the one pointer the place holds.
Value boxOf(OpBuilder &b, Location loc, Runtime &runtime, Value address,
            const layout::Element &element) {
  return runtime.load(b, loc, address, elementAlignment(element), element.slots).front();
}

} // namespace

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

Taken takeElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                  Value address, const layout::Element &element, Type type) {
  if (!element.boxed)
    return {readElement(b, loc, runtime, address, element), Value()};
  Value cell = boxOf(b, loc, runtime, address, element);
  SmallVector<Value> value =
      runtime.load(b, loc, cell, cellAlignment(), element.boxed->fields.front());
  // Whether a copy of the array shares the box is known only at run time:
  // a copy shares every box of the array it copies. Held by the place
  // alone, the box keeps its memory for the value put back; shared, it
  // keeps its value, which gains a reference of its own, and loses the
  // place's, and the value put back goes into a box of its own.
  auto alone = scf::IfOp::create(b, loc, ptrType(b.getContext()),
                                 runtime.isUnique(b, loc, cell), /*withElseRegion=*/true);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(alone.thenBlock());
  scf::YieldOp::create(b, loc, cell);
  b.setInsertionPointToStart(alone.elseBlock());
  runtime.inc(b, loc, layouts.components(type), value);
  runtime.dec(b, loc, layout::Word::Cell, cell);
  scf::YieldOp::create(b, loc, runtime.allocate(b, loc, *element.boxed));
  return {std::move(value), alone.getResult(0)};
}

void putBack(OpBuilder &b, Location loc, Runtime &runtime, Value address,
             const layout::Element &element, const Taken &taken, ValueRange value) {
  if (!element.boxed) {
    placeElement(b, loc, runtime, address, element, value);
    return;
  }
  runtime.store(b, loc, taken.box, cellAlignment(), element.boxed->fields.front(), value);
  runtime.store(b, loc, address, elementAlignment(element), element.slots, taken.box);
}

} // namespace idr::conversion
