// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The place of an element of an array (Elements.h): its slots in place, or
// one counted pointer to a cell of its own; its value read with no
// reference of its own, written over what it held, put where nothing is
// held, and moved out with the place's references.

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
  Value cell = runtime.allocate(b, loc, *element.boxed, 0);
  runtime.store(b, loc, cell, cellAlignment(), element.boxed->fields.front(), value);
  runtime.store(b, loc, address, elementAlignment(element), element.slots, cell);
}

void writeElement(OpBuilder &b, Location loc, Runtime &runtime, const Layouts &layouts,
                  Value address, const layout::Element &element, Type type, ValueRange value) {
  if (element.boxed) {
    runtime.dec(b, loc, boxOf(b, loc, runtime, address, element), {true});
  } else {
    SmallVector<bool> counted = layouts.counted(type);
    if (llvm::is_contained(counted, true))
      runtime.dec(b, loc, readElement(b, loc, runtime, address, element), counted);
  }
  placeElement(b, loc, runtime, address, element, value);
}

SmallVector<Value> takeElement(OpBuilder &b, Location loc, Runtime &runtime,
                               const Layouts &layouts, Value address,
                               const layout::Element &element, Type type) {
  if (!element.boxed)
    return readElement(b, loc, runtime, address, element);
  Value cell = boxOf(b, loc, runtime, address, element);
  SmallVector<Value> value =
      runtime.load(b, loc, cell, cellAlignment(), element.boxed->fields.front());
  // The cell alone holds the value: its memory goes and the value moves
  // out. A cell a copy shares keeps the value, which gains a reference of
  // its own, and loses the place's.
  auto alone = scf::IfOp::create(b, loc, runtime.exclusive(b, loc, cell), /*withElseRegion=*/true);
  OpBuilder::InsertionGuard guard(b);
  b.setInsertionPointToStart(alone.thenBlock());
  runtime.call(b, loc, "idris_rt_free_cell", Type(), cell);
  b.setInsertionPointToStart(alone.elseBlock());
  runtime.inc(b, loc, value, layouts.counted(type));
  runtime.dec(b, loc, cell, {true});
  return value;
}

} // namespace idr::conversion
