// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folders of the big ops: each calls the runtime's function of its op
// on its constant operands, as Fold.h says.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"

using namespace mlir;

namespace idr {

using fold::bigBinary;
using fold::bigUnary;
using fold::compared;
using fold::runtimeOfWord;
using fold::Scope;
using fold::strUnary;
using fold::wrapped;

OpFoldResult BigAddOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigAddOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigSubOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigSubOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigMulOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigMulOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigAndOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigAndOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigOrOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigOrOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigXorOp::fold(FoldAdaptor adaptor) {
  return bigBinary<BigXorOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}

namespace {

// Whether shifting the constant `value` by `amount` (left when `left`, the
// other way when the amount is negative) makes a constant within
// constantBytes. The runtime computes the fold here, in the compiler, so a
// result past the budget is never made. A shift toward zero, or of 0,
// shrinks or keeps its operand; one away from zero has at most the
// operand's bits plus the amount. An amount past 2^64 is past every budget.
bool foldable(BigAttr value, BigAttr amount, bool left) {
  const APInt &places = amount.getValue();
  if (left == places.isNegative() || value.getValue().isZero())
    return true;
  constexpr uint64_t bits = 8 * constantBytes;
  std::optional<uint64_t> count = places.abs().tryZExtValue();
  return count && *count <= bits && value.getValue().getSignificantBits() <= bits - *count;
}

template <typename OpT>
OpFoldResult bigShift(OpT op, typename OpT::FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  auto amount = dyn_cast_or_null<BigAttr>(adaptor.getAmount());
  if (!value || !amount || !foldable(value, amount, OpT::left))
    return {};
  return bigBinary<OpT>(op.getContext(), value, amount);
}

} // namespace

OpFoldResult BigShlOp::fold(FoldAdaptor adaptor) { return bigShift(*this, adaptor); }
OpFoldResult BigShrOp::fold(FoldAdaptor adaptor) { return bigShift(*this, adaptor); }

// Nothing by a divisor its guard refuses, zero: the program never divides
// by it, since the guard crashes first.
OpFoldResult BigDivOp::fold(FoldAdaptor adaptor) {
  if (!CheckNonzeroOp::holds({adaptor.getRhs()}))
    return {};
  return bigBinary<BigDivOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigModOp::fold(FoldAdaptor adaptor) {
  if (!CheckNonzeroOp::holds({adaptor.getRhs()}))
    return {};
  return bigBinary<BigModOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}

OpFoldResult BigNegOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(fold::runtime<BigNegOp>(a));
  });
}

// Zero has no predecessor: a constant zero is on a path the match before
// it excludes, and stays as it is.
OpFoldResult BigPredOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a || a.getValue().isZero())
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<BigPredOp>(scope.big(a)));
}

// The constant is the same value under the other type, which the
// constant that materializes it takes from the op's result.
OpFoldResult NatToBigOp::fold(FoldAdaptor adaptor) {
  return dyn_cast_or_null<BigAttr>(adaptor.getValue());
}

OpFoldResult NatFromBigOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(fold::runtime<NatFromBigOp>(a));
  });
}

OpFoldResult BigCmpOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getLhs()), b = dyn_cast_or_null<BigAttr>(adaptor.getRhs());
  if (!a || !b)
    return {};
  Scope scope(getContext());
  return compared(getContext(), getPredicate(), fold::runtime<BigCmpOp>(scope.big(a), scope.big(b)));
}

OpFoldResult BigFromIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(runtimeOfWord<BigFromIntOp>(n, getIsSigned()));
}

// A small is the Integer of its word, read signed, as big.from_int makes
// it.
OpFoldResult BigSmallOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(runtimeOfWord<BigFromIntOp>(n, /*isSigned=*/true));
}

OpFoldResult BigToIntOp::fold(FoldAdaptor adaptor) {
  // An integer made a big and back at its own width is itself, whichever
  // way it was read: idr-narrow leaves these pairs where a word meets a
  // word.
  if (auto from = getValue().getDefiningOp<BigFromIntOp>())
    if (from.getValue().getType() == getType())
      return from.getValue();
  if (auto small = getValue().getDefiningOp<BigSmallOp>())
    if (small.getValue().getType() == getType())
      return small.getValue();
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return wrapped(getType(), fold::runtime<BigToIntOp>(scope.big(a)));
}

// Nothing of a Double its guard refuses, one that is not finite.
OpFoldResult BigFromDoubleOp::fold(FoldAdaptor adaptor) {
  if (!CheckFiniteOp::holds({adaptor.getValue()}))
    return {};
  auto d = cast<FloatAttr>(adaptor.getValue());
  Scope scope(getContext());
  return scope.attr(fold::runtime<BigFromDoubleOp>(d.getValueAsDouble()));
}

OpFoldResult BigToDoubleOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return bigUnary(getContext(), adaptor.getValue(), [&](Scope &, idris_rt_big a) {
    return FloatAttr::get(type, fold::runtime<BigToDoubleOp>(a));
  });
}

OpFoldResult BigShowOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(fold::runtime<BigShowOp>(a));
  });
}

OpFoldResult BigFromStrOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(fold::runtime<BigFromStrOp>(s));
  });
}

} // namespace idr
