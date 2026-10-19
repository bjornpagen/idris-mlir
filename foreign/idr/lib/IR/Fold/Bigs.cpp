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
using fold::Scope;
using fold::strUnary;
using fold::wrapped;

namespace {

// Whether a constant is the big zero.
bool isZero(Attribute value) {
  auto big = dyn_cast_or_null<BigAttr>(value);
  return big && big.getValue().isZero();
}

} // namespace

// The sum of two constants, by the runtime; and a sum with zero, on either
// side, is the other operand where that operand is at the sum's type. The
// type is essential: after idr-rc a big op reads views and owns its result,
// so an owned sum is never replaced by a view.
OpFoldResult BigAddOp::fold(FoldAdaptor adaptor) {
  if (OpFoldResult sum = bigBinary<BigAddOp>(getContext(), adaptor.getLhs(), adaptor.getRhs()))
    return sum;
  if (isZero(adaptor.getRhs()) && getLhs().getType() == getType())
    return getLhs();
  if (isZero(adaptor.getLhs()) && getRhs().getType() == getType())
    return getRhs();
  return {};
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
// constantBytes, the size policy of a constant a fold makes. The runtime
// computes the fold here, in the compiler, so a result past it is never
// made, and the shift stays an op. A shift toward zero, or of 0, shrinks or
// keeps its operand; one away from zero has at most the operand's bits
// plus the amount. An amount past 2^64 is past any such size.
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
  if (!guardHolds(adaptor))
    return {};
  return bigBinary<BigDivOp>(getContext(), adaptor.getLhs(), adaptor.getRhs());
}
OpFoldResult BigModOp::fold(FoldAdaptor adaptor) {
  if (!guardHolds(adaptor))
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

// An integer's big by the op's own function: the integer extended to the
// function's word as the op reads it, sign-extended when signed and
// zero-extended when not.
OpFoldResult BigFromSIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<BigFromSIntOp>(n.getValue().getSExtValue()));
}

OpFoldResult BigFromUIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<BigFromUIntOp>(n.getValue().getZExtValue()));
}

// A small is the Integer of its word, read signed, as big.from_sint makes
// it: that function has a big for every word, where the small's own has one
// only for a word that fits.
OpFoldResult BigSmallOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<BigFromSIntOp>(n.getValue().getSExtValue()));
}

OpFoldResult BigToIntOp::fold(FoldAdaptor adaptor) {
  // An integer made a big and back at its own width is itself, whichever
  // way it was read, through any view of the big: idr-narrow leaves these
  // pairs where a word meets a word.
  Value big = getValue();
  for (Operation *def = big.getDefiningOp(); def && def->hasTrait<ResultCarriesOperand>();
       def = big.getDefiningOp())
    big = def->getOperand(0);
  if (Operation *from = big.getDefiningOp();
      isa_and_nonnull<BigFromSIntOp, BigFromUIntOp, BigSmallOp>(from) &&
      from->getOperand(0).getType() == getType())
    return from->getOperand(0);
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return wrapped(getType(), fold::runtime<BigToIntOp>(scope.big(a)));
}

// Nothing of a Double its guard refuses, one that is not finite.
OpFoldResult BigFromDoubleOp::fold(FoldAdaptor adaptor) {
  if (!guardHolds(adaptor))
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
