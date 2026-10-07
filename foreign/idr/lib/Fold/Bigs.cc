// The folders of the big ops: each calls the runtime's own C function on its
// constant operands, as idr.fold says.

#include "idr/Idr.h"

#include "idris_rt.h"

import idr.fold;

using namespace mlir;

namespace idr {

using fold::bigBinary;
using fold::bigDivision;
using fold::bigUnary;
using fold::compared;
using fold::extended;
using fold::Scope;
using fold::strUnary;
using fold::wrapped;

OpFoldResult BigAddOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_add);
}
OpFoldResult BigSubOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_sub);
}
OpFoldResult BigMulOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_mul);
}
OpFoldResult BigAndOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_and);
}
OpFoldResult BigOrOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_or);
}
OpFoldResult BigXorOp::fold(FoldAdaptor adaptor) {
  return bigBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_xor);
}
OpFoldResult BigDivOp::fold(FoldAdaptor adaptor) {
  return bigDivision(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_div);
}
OpFoldResult BigModOp::fold(FoldAdaptor adaptor) {
  return bigDivision(getContext(), adaptor.getLhs(), adaptor.getRhs(), idris_rt_big_mod);
}

OpFoldResult BigNegOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(idris_rt_big_neg(a));
  });
}

// Zero has no predecessor: a constant zero is on a path the match before
// it excludes, and stays as it is.
OpFoldResult BigPredOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a || a.getValue() == "0")
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_big_pred(scope.big(a)));
}

// The constant is the same value under the other type, which the
// constant that materializes it takes from the op's result.
OpFoldResult NatToBigOp::fold(FoldAdaptor adaptor) {
  return dyn_cast_or_null<BigAttr>(adaptor.getValue());
}

OpFoldResult NatFromBigOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(idris_rt_nat_from_big(a));
  });
}

OpFoldResult BigCmpOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getLhs()), b = dyn_cast_or_null<BigAttr>(adaptor.getRhs());
  if (!a || !b)
    return {};
  Scope scope(getContext());
  return compared(getContext(), getPredicate(), idris_rt_big_cmp(scope.big(a), scope.big(b)));
}

OpFoldResult BigFromIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  int64_t value = extended(n, getIsSigned());
  return scope.attr(getIsSigned() ? idris_rt_big_from_int_s(value)
                                  : idris_rt_big_from_int_u(static_cast<uint64_t>(value)));
}

OpFoldResult BigSmallOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_big_from_int_s(n.getValue().getSExtValue()));
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
  return wrapped(getType(), idris_rt_big_to_int(scope.big(a)));
}

OpFoldResult BigFromDoubleOp::fold(FoldAdaptor adaptor) {
  auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!d || !d.getValue().isFinite())
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_big_from_double(d.getValueAsDouble()));
}

OpFoldResult BigToDoubleOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return bigUnary(getContext(), adaptor.getValue(), [&](Scope &, idris_rt_big a) {
    return FloatAttr::get(type, idris_rt_big_to_double(a));
  });
}

OpFoldResult BigShowOp::fold(FoldAdaptor adaptor) {
  return bigUnary(getContext(), adaptor.getValue(), [](Scope &scope, idris_rt_big a) {
    return scope.attr(idris_rt_big_show(a));
  });
}

OpFoldResult BigFromStrOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(idris_rt_big_from_str(s));
  });
}

} // namespace idr
