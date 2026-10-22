// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The two domains of the inline meanings that need MLIR: intervals, each
// operation upstream's transfer function for its arith op, and arith ops
// built at a builder, each the arith op itself, folded on constants. And
// the conversion between an integer constant and a word.

#include "idr/IR/Numeric/Arith.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/Numeric/Trait.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"
#include "llvm/ADT/APInt.h"

using namespace mlir;

namespace idr::numeric {

//===----------------------------------------------------------------------===//
// Words and constants
//===----------------------------------------------------------------------===//

Word wordOf(IntegerAttr constant) {
  const APInt &value = constant.getValue();
  return Words::of(value.getZExtValue(), value.getBitWidth());
}

IntegerAttr attrOf(Type type, Word word) {
  return IntegerAttr::get(type, APInt(word.width, word.bits));
}

//===----------------------------------------------------------------------===//
// Intervals
//===----------------------------------------------------------------------===//

namespace {

// A truth intervals decide, from a predicate upstream evaluates on them.
KnownTruth decided(std::optional<bool> answer) {
  if (!answer)
    return {Known::Unknown};
  return {*answer ? Known::Holds : Known::Fails};
}

} // namespace

unsigned Intervals::width(const Value &a) const { return a.umin().getBitWidth(); }

// The constant at the width, its bits modulo 2^width, as a word's.
Intervals::Value Intervals::constant(std::int64_t c, const Value &like) const {
  return Value::constant(
      APInt(width(like), static_cast<uint64_t>(c), /*isSigned=*/false, /*implicitTrunc=*/true));
}

Intervals::Value Intervals::least(const Value &like) const {
  return Value::constant(APInt::getSignedMinValue(width(like)));
}

Intervals::Value Intervals::add(const Value &a, const Value &b) const {
  return intrange::inferAdd({a, b});
}
Intervals::Value Intervals::sub(const Value &a, const Value &b) const {
  return intrange::inferSub({a, b});
}
Intervals::Value Intervals::bitAnd(const Value &a, const Value &b) const {
  return intrange::inferAnd({a, b});
}
Intervals::Value Intervals::quotientTowardZero(const Value &a,
                                               const SafeDivisor<Intervals> &s) const {
  return intrange::inferDivS({a, s.value()});
}
Intervals::Value Intervals::remainderTowardZero(const Value &a,
                                                const SafeDivisor<Intervals> &s) const {
  return intrange::inferRemS({a, s.value()});
}
Intervals::Value Intervals::shiftLeft(const Value &a, const BelowWidth<Intervals> &n) const {
  return intrange::inferShl({a, n.value()});
}
Intervals::Value Intervals::shiftRightArithmetic(const Value &a,
                                                 const BelowWidth<Intervals> &n) const {
  return intrange::inferShrS({a, n.value()});
}
Intervals::Value Intervals::shiftRightLogical(const Value &a,
                                              const BelowWidth<Intervals> &n) const {
  return intrange::inferShrU({a, n.value()});
}

// Widening to the same width is the interval itself, as a word's.
Intervals::Value Intervals::extendSigned(const Value &a, unsigned to) const {
  return to == width(a) ? a : intrange::extSIRange(a, to);
}
Intervals::Value Intervals::extendUnsigned(const Value &a, unsigned to) const {
  return to == width(a) ? a : intrange::extUIRange(a, to);
}
Intervals::Value Intervals::truncate(const Value &a, unsigned to) const {
  return to == width(a) ? a : intrange::truncRange(a, to);
}

KnownTruth Intervals::equal(const Value &a, const Value &b) const {
  return decided(intrange::evaluatePred(intrange::CmpPredicate::eq, a, b));
}
KnownTruth Intervals::lessSigned(const Value &a, const Value &b) const {
  return decided(intrange::evaluatePred(intrange::CmpPredicate::slt, a, b));
}
KnownTruth Intervals::lessUnsigned(const Value &a, const Value &b) const {
  return decided(intrange::evaluatePred(intrange::CmpPredicate::ult, a, b));
}

// Kleene's three-valued conjunction, disjunction and negation: a failing
// side decides a conjunction, a holding side a disjunction.
KnownTruth Intervals::both(KnownTruth t, KnownTruth u) const {
  if (t.known == Known::Fails || u.known == Known::Fails)
    return {Known::Fails};
  if (t.known == Known::Holds && u.known == Known::Holds)
    return {Known::Holds};
  return {Known::Unknown};
}
KnownTruth Intervals::either(KnownTruth t, KnownTruth u) const {
  if (t.known == Known::Holds || u.known == Known::Holds)
    return {Known::Holds};
  if (t.known == Known::Fails && u.known == Known::Fails)
    return {Known::Fails};
  return {Known::Unknown};
}
KnownTruth Intervals::negation(KnownTruth t) const {
  switch (t.known) {
  case Known::Holds:
    return {Known::Fails};
  case Known::Fails:
    return {Known::Holds};
  case Known::Unknown:
    return {Known::Unknown};
  }
  return t;
}

Intervals::Value Intervals::select(KnownTruth t, const Value &a, const Value &b) const {
  switch (t.known) {
  case Known::Holds:
    return a;
  case Known::Fails:
    return b;
  case Known::Unknown:
    return a.rangeUnion(b);
  }
  return a.rangeUnion(b);
}

//===----------------------------------------------------------------------===//
// arith
//===----------------------------------------------------------------------===//

unsigned Arith::width(Value a) const { return a.getType().getIntOrFloatBitWidth(); }

// The constant at the value's type, its bits modulo 2^width.
Arith::Value Arith::constant(std::int64_t c, Value like) const {
  Type type = like.getType();
  return arith::ConstantOp::create(
      b, loc,
      IntegerAttr::get(type, APInt(width(like), static_cast<uint64_t>(c), /*isSigned=*/false,
                                   /*implicitTrunc=*/true)));
}

Arith::Value Arith::least(Value like) const {
  return arith::ConstantOp::create(
      b, loc, IntegerAttr::get(like.getType(), APInt::getSignedMinValue(width(like))));
}

Arith::Value Arith::add(Value x, Value y) const { return b.createOrFold<arith::AddIOp>(loc, x, y); }
Arith::Value Arith::sub(Value x, Value y) const { return b.createOrFold<arith::SubIOp>(loc, x, y); }
Arith::Value Arith::bitAnd(Value x, Value y) const {
  return b.createOrFold<arith::AndIOp>(loc, x, y);
}
Arith::Value Arith::quotientTowardZero(Value x, const SafeDivisor<Arith> &s) const {
  return b.createOrFold<arith::DivSIOp>(loc, x, s.value());
}
Arith::Value Arith::remainderTowardZero(Value x, const SafeDivisor<Arith> &s) const {
  return b.createOrFold<arith::RemSIOp>(loc, x, s.value());
}
Arith::Value Arith::shiftLeft(Value x, const BelowWidth<Arith> &n) const {
  return b.createOrFold<arith::ShLIOp>(loc, x, n.value());
}
Arith::Value Arith::shiftRightArithmetic(Value x, const BelowWidth<Arith> &n) const {
  return b.createOrFold<arith::ShRSIOp>(loc, x, n.value());
}
Arith::Value Arith::shiftRightLogical(Value x, const BelowWidth<Arith> &n) const {
  return b.createOrFold<arith::ShRUIOp>(loc, x, n.value());
}

// arith's casts take a strictly wider or narrower type: the same width is
// the value itself.
Arith::Value Arith::extendSigned(Value x, unsigned to) const {
  if (to == width(x))
    return x;
  return b.createOrFold<arith::ExtSIOp>(loc, b.getIntegerType(to), x);
}
Arith::Value Arith::extendUnsigned(Value x, unsigned to) const {
  if (to == width(x))
    return x;
  return b.createOrFold<arith::ExtUIOp>(loc, b.getIntegerType(to), x);
}
Arith::Value Arith::truncate(Value x, unsigned to) const {
  if (to == width(x))
    return x;
  return b.createOrFold<arith::TruncIOp>(loc, b.getIntegerType(to), x);
}

Condition Arith::equal(Value x, Value y) const {
  return {b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::eq, x, y)};
}
Condition Arith::lessSigned(Value x, Value y) const {
  return {b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::slt, x, y)};
}
Condition Arith::lessUnsigned(Value x, Value y) const {
  return {b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::ult, x, y)};
}
Condition Arith::both(Condition t, Condition u) const {
  return {b.createOrFold<arith::AndIOp>(loc, t.bit, u.bit)};
}
Condition Arith::either(Condition t, Condition u) const {
  return {b.createOrFold<arith::OrIOp>(loc, t.bit, u.bit)};
}
Condition Arith::negation(Condition t) const {
  Value yes = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
  return {b.createOrFold<arith::XOrIOp>(loc, t.bit, yes)};
}
Arith::Value Arith::select(Condition t, Value x, Value y) const {
  return b.createOrFold<arith::SelectOp>(loc, t.bit, x, y);
}

} // namespace idr::numeric
