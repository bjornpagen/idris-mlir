// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// arith ops built at a builder's insertion point, the domain an inline op's
// expansion is computed over: a value is an mlir::Value of the op's integer
// type, a truth an i1 value, and every operation builds the arith op it is,
// folded where its operands are constants (createOrFold), so a shift by a
// constant amount expands to one arith shift. No operation builds poison:
// division takes a SafeDivisor and a shift a BelowWidth (Domain.h), which
// only the meanings mint.
//
// The expansion is emitted at the stage that needs arith (the lowering, and
// the vectorization's preparation); until then the op keeps the fact of
// what it is, as arith.floordivsi stays an op until arith-expand.
#ifndef IDR_IR_NUMERIC_ARITH_H
#define IDR_IR_NUMERIC_ARITH_H

#include "idr/IR/Numeric/Domain.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Value.h"

#include <cstdint>

namespace idr::numeric {

// An i1 value, with no conversion to bool (an mlir::Value has one: null or
// not, which a meaning must never branch on).
struct Condition {
  mlir::Value bit;
};

class Arith {
public:
  using Value = mlir::Value;
  using Truth = Condition;
  static constexpr Overflow overflow = Overflow::Wraps;

  Arith(mlir::OpBuilder &builder, mlir::Location loc) : b(builder), loc(loc) {}

  unsigned width(Value a) const;
  Value constant(std::int64_t c, Value like) const;
  Value least(Value like) const;

  Value add(Value a, Value c) const;
  Value sub(Value a, Value c) const;
  Value bitAnd(Value a, Value c) const;
  Value quotientTowardZero(Value a, const SafeDivisor<Arith> &s) const;
  Value remainderTowardZero(Value a, const SafeDivisor<Arith> &s) const;
  Value shiftLeft(Value a, const BelowWidth<Arith> &n) const;
  Value shiftRightArithmetic(Value a, const BelowWidth<Arith> &n) const;
  Value shiftRightLogical(Value a, const BelowWidth<Arith> &n) const;
  Value extendSigned(Value a, unsigned width) const;
  Value extendUnsigned(Value a, unsigned width) const;
  Value truncate(Value a, unsigned width) const;

  Condition equal(Value a, Value c) const;
  Condition lessSigned(Value a, Value c) const;
  Condition lessUnsigned(Value a, Value c) const;
  Condition both(Condition t, Condition u) const;
  Condition either(Condition t, Condition u) const;
  Condition negation(Condition t) const;
  Value select(Condition t, Value a, Value c) const;

private:
  mlir::OpBuilder &b;
  mlir::Location loc;
};

static_assert(Domain<Arith>);

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_ARITH_H
