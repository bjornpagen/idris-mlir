// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The grade's one op, idr.lin.cast: a value cast into or out of a linear
// position, its hold kept or its claim forgotten on the way. It passes its
// operand through, so a scoped result lives where its operand does or in a
// lifetime that one encloses, which it states by its entry of `outers`, as
// every op that makes a scoped value does. And how a pass holds a value at
// another grade of its carrier: the cast where the uses change, a share
// where only the hold does.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ranges.h"

using namespace mlir;
using namespace idr;

// Between types of one carrier: the cast where the uses differ, whose
// direction its types say, the hold kept or its claim forgotten on the
// way; a share where only the hold does, which the cast is not, its claim
// forgotten or static data given where a value that claims nothing is
// asked; and nothing at the same grade.
Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  if (usesOf(value.getType()) == usesOf(type))
    return CountShareOp::create(b, loc, type, value);
  return LinCastOp::create(b, loc, type, value);
}

// A cast of a value a pass has in hand states the operand's own lifetime
// for a scoped result, the longest it may state, one hop from the operand.
void LinCastOp::build(OpBuilder &builder, OperationState &state, Type result, Value value) {
  Value lifetime = freedBy(result, Release::Scoped) ? lifetimes::statedLifetime(value) : Value();
  build(builder, state, result, value, lifetime ? ValueRange(lifetime) : ValueRange());
}

// The cast is between types of one carrier at other uses, its hold the
// operand's or one it fits by the grade order: a claim may be forgotten,
// and raised only by a cast that enters a value used many times into a
// position as its one use, to what the value's cell holds where every other
// use of it is a read that ends before the cast, which the local rule judges
// in the function's walk (ownership::entryOf), since it reads the value's
// other uses; no cast proves more than that. A scoped result states its
// lifetime.
LogicalResult LinCastOp::verify() {
  Type from = getValue().getType();
  Type to = getType();
  if (unrestricted(from) != unrestricted(to) || usesOf(from) == usesOf(to))
    return emitOpError("casts ") << from << " to " << to
                                 << ", which differ in more than their grades or not in their uses";
  bool raisesClaim = getDirection() == QuantityChange::Enter && holdFits(from, shared(to));
  if (!holdFits(from, to) && !raisesClaim)
    return emitOpError("casts ") << from << " to " << to
                                 << ", whose hold claims more or is freed otherwise";
  return lifetimes::verifyOuters(*this, 0);
}

Value LinCastOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void LinCastOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

QuantityChange LinCastOp::getDirection() {
  return usesOf(getType()) == Uses::Once ? QuantityChange::Enter : QuantityChange::Leave;
}

// Its meaning's attribute instance (Ops/Folds.h).
OpFoldResult LinCastOp::fold(FoldAdaptor adaptor) {
  fold::InParts where(getContext());
  return fold::foldResultOf(meaning(where, *this, adaptor.getOperands()));
}

void LinCastOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                              SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}
