// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grade's one op, idr.lin.cast: a value cast into or out of a linear
// position. It passes its operand through, so a scoped result lives where
// its operand does or in a lifetime that one encloses, which it states by
// its entry of `outers`, as every op that makes a scoped value does.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ranges.h"

using namespace mlir;
using namespace idr;

// One cast between types equal up to their uses, whose direction its types
// say.
Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  return LinCastOp::create(b, loc, type, value);
}

// A cast of a value a pass has in hand states the operand's own lifetime
// for a scoped result, the longest it may state, one hop from the operand.
void LinCastOp::build(OpBuilder &builder, OperationState &state, Type result, Value value) {
  Value lifetime = freedBy(result, Release::Scoped) ? lifetimes::statedLifetime(value) : Value();
  build(builder, state, result, value, lifetime ? ValueRange(lifetime) : ValueRange());
}

// The cast is between types equal but for their uses: the same carrier at
// the same hold, the other uses; a scoped result states its lifetime.
LogicalResult LinCastOp::verify() {
  Type from = getValue().getType();
  Type to = getType();
  if (unrestricted(from) != unrestricted(to) || holdOf(from) != holdOf(to) ||
      usesOf(from) == usesOf(to))
    return emitOpError("casts ") << from << " to " << to
                                 << ", which differ in more than their uses or not in them";
  return lifetimes::verifyOuters(*this, 0);
}

Value LinCastOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void LinCastOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

QuantityChange LinCastOp::getDirection() {
  return usesOf(getType()) == Uses::Once ? QuantityChange::Enter : QuantityChange::Leave;
}

// The QTT rule: a cast back of a cast whose result nothing else uses is the
// value itself, nothing having run in the linear position; a value cast
// into a linear position and used elsewhere too stays, since folding it
// would use the value twice. The value lives at least as long as either
// cast states, so what used the outer cast may use it.
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
