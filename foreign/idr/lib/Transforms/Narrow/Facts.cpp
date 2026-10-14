// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bounds of values, as the analysis found them and as the pass makes
// them, and the words and bigs that stand for each other.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Narrow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ownership.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::narrow {

using ranges::Bounds;

bool isBig(Type type) { return isa<BigType, NatType>(unrestricted(type)); }

// Once counting ran, the grade says whether a big holds a reference of its
// own, and a value that stands for one (a small big, poison) holds none.
bool Facts::owned(Value value) const {
  return analysis.counted() && isOwned(value.getType()) && !ownership::isStatic(value);
}

bool Facts::borrowed(Value value) const {
  return analysis.counted() && !isOwned(value.getType()) && !ownership::isStatic(value);
}

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
  Bounds bounds = ranges::boundsOf(*range);
  if (isa<NatType>(value.getType()) && bounds.hi && (!bounds.lo || *bounds.lo < 0))
    bounds.lo = 0;
  return bounds;
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
  if (auto small = value.getDefiningOp<BigSmallOp>())
    return small.getValue();
  if (auto from = value.getDefiningOp<BigFromIntOp>()) {
    Value source = from.getValue();
    if (source.getType() == i64)
      return source;
    return from.getIsSigned() ? Value(arith::ExtSIOp::create(b, loc, i64, source))
                              : Value(arith::ExtUIOp::create(b, loc, i64, source));
  }
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
