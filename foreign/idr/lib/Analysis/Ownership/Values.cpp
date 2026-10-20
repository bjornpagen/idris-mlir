// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which values hold references, as their types answer, and which ones
// exclusivity follows.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;

namespace idr::ownership {

// Owned boxes and unboxed sums, whose slots may hold boxes, and the tokens
// of their cells: what a take hands out or a recycled cell is made of. A
// cell is memory, not a reference, so it has no grade to say it is owned;
// the box its init gives is its cell's, new to anyone when the cell is (a
// fresh or recycled cell) and not when it is the frame's (idr.cell.stack).
bool followed(Value value) {
  Type type = value.getType();
  return isa<CellType>(type) ||
         (isOwned(type) && isa<BoxType, DataType, TokenType>(unrestricted(type)));
}

// The type answers, a data type from its body, made once: asking again
// costs nothing, so no pass keeps answers of its own.
bool tracked(Value value) { return holdsReferences(value.getType()) && !isStatic(value); }

bool isMemoCell(Type type) {
  auto box = dyn_cast<BoxType>(unrestricted(type));
  return box && box.getData().isMemo();
}

bool isCountedElement(Value value) {
  auto load = value.getDefiningOp<memref::LoadOp>();
  return load && holdsReferences(load.getType());
}

} // namespace idr::ownership
