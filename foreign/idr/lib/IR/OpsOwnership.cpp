// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The hooks of the grade's one op, the cast of a value into or out of a
// linear position (idr.lin.cast): its rule, its direction, the QTT fold,
// and its operand's range, since it changes only the value's uses; and of
// the arena cell (idr.cell.arena), which puts one cell's bytes into its
// lifetime. The lifetime's own ops are lib/IR/Lifetimes/; the slot
// (idr.cell.stack) says all it does in its declaration, and the function
// verifier holds it to its lifetime's run.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ranges.h"

using namespace mlir;
using namespace idr;

// The cast is between types equal but for their uses: the same carrier at
// the same hold, the other uses.
LogicalResult LinCastOp::verify() {
  Type from = getValue().getType();
  Type to = getType();
  if (unrestricted(from) != unrestricted(to) || holdOf(from) != holdOf(to) ||
      usesOf(from) == usesOf(to))
    return emitOpError("casts ") << from << " to " << to
                                 << ", which differ in more than their uses or not in them";
  return success();
}

QuantityChange LinCastOp::getDirection() {
  return usesOf(getType()) == Uses::Once ? QuantityChange::Enter : QuantityChange::Leave;
}

// The QTT rule: a cast back of a cast whose result nothing else uses is the
// value itself, nothing having run in the linear position; a value cast
// into a linear position and used elsewhere too stays, since folding it
// would use the value twice.
OpFoldResult LinCastOp::fold(FoldAdaptor) {
  auto inner = getValue().getDefiningOp<LinCastOp>();
  if (!inner || inner.getValue().getType() != getType() || !inner->hasOneUse())
    return {};
  return inner.getValue();
}

void LinCastOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                              SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}

Value CellArenaOp::getPutLifetime() { return getLifetime(); }

// The cell's allocation size, its constructor's in its family's cells.
std::uint64_t CellArenaOp::getPutBytes(const Layouts &layouts) {
  auto cell = cast<CellType>(getCell().getType());
  return layouts.cells(cell.getData()).cell(cell.getTag()).size;
}
