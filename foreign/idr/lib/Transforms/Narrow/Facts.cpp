// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bounds of values, as the analysis found them and as the pass makes
// them, and the words and bigs that stand for each other.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Narrow.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::narrow {

using ranges::Bounds;

bool isBig(Type type) { return isa<BigType, NatType>(unrestricted(type)); }

namespace {

// `source`, an integer of at most 64 bits, as an i64, extended by
// `Extend`.
template <typename Extend>
Value widened(OpBuilder &b, Location loc, Value source) {
  Type i64 = b.getI64Type();
  if (source.getType() == i64)
    return source;
  return Extend::create(b, loc, i64, source).getResult();
}

} // namespace

// The grade says whether a big holds a reference of its own: freed by its
// count. Static data, which its type says is static, holds none.
bool Facts::owned(Value value) const { return freedBy(value.getType(), Release::Counted); }

// A view holds references and none of its own: freed when its lifetime
// ends.
bool Facts::borrowed(Value value) const { return freedBy(value.getType(), Release::Scoped); }

Bounds Facts::of(Value value) const {
  // The program's poison may be taken to be any value, so a small one.
  if (value.getDefiningOp<ub::PoisonOp>())
    return {0, 0};
  if (auto it = madeBounds.find(value); it != madeBounds.end())
    return it->second;
  // Code the analysis never reached has no range, and proves nothing.
  std::optional<ConstantIntRanges> range = analysis.rangeOf(value);
  if (!range)
    return {};
  // What the value's type proves holds wherever the analysis lost it, as a
  // natural's lower bound 0; a type that proves no range leaves the
  // analysis's as it is.
  IntegerValueRange proved = ranges::ofType(value.getType());
  if (!proved.isUninitialized())
    range = range->intersection(proved.getValue());
  return ranges::boundsOf(*range);
}

bool Facts::nonNegative(ValueRange values) const {
  return llvm::all_of(values, [&](Value v) {
    Bounds b = of(v);
    return b.lo && *b.lo >= 0;
  });
}

Value Facts::word(OpBuilder &b, Location loc, Value value) {
  auto i64 = b.getI64Type();
  if (auto poison = value.getDefiningOp<ub::PoisonOp>()) {
    // The word of the program's poison is poison: no conversion runs on a
    // path that never reads it. The big poison goes once nothing reads it.
    convert(poison);
    return ub::PoisonOp::create(b, loc, i64);
  }
  // What made the big, through the ops that only change its grade (the
  // view counting reads it through).
  Value made = value;
  for (Operation *def = made.getDefiningOp(); def && def->hasTrait<ResultCarriesOperand>();
       def = made.getDefiningOp())
    made = def->getOperand(0);
  if (auto small = made.getDefiningOp<BigSmallOp>())
    return small.getValue();
  // A big made of a narrower integer is that integer, extended as the op
  // that made it reads it.
  if (auto from = made.getDefiningOp<BigFromSIntOp>())
    return widened<arith::ExtSIOp>(b, loc, from.getValue());
  if (auto from = made.getDefiningOp<BigFromUIntOp>())
    return widened<arith::ExtUIOp>(b, loc, from.getValue());
  // A big is read in place at any hold, so its conversion takes nothing of
  // it.
  Value converted = BigToIntOp::create(b, loc, i64, value);
  convert(converted.getDefiningOp());
  return converted;
}

Value Facts::big(OpBuilder &b, Location loc, Type type, Value word, Bounds bounds) {
  Value value = BigSmallOp::create(b, loc, type, word);
  madeBounds[value] = bounds;
  convert(value.getDefiningOp());
  return value;
}

} // namespace idr::narrow
