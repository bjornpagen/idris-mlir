// The folders of the string ops: each calls the runtime's own C function on
// its constant operands, as idr.fold says.

#include "idr/Idr.h"

#include "idris_rt.h"

import idr.fold;

using namespace mlir;

namespace idr {

using fold::compared;
using fold::extended;
using fold::Scope;
using fold::strBinary;
using fold::strUnary;
using fold::wrapped;

OpFoldResult StrAppendOp::fold(FoldAdaptor adaptor) {
  return strBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(),
                   [](Scope &scope, const idris_rt_str *a, const idris_rt_str *b) {
                     return scope.attr(idris_rt_str_append(a, b));
                   });
}

OpFoldResult StrConsOp::fold(FoldAdaptor adaptor) {
  auto c = dyn_cast_or_null<IntegerAttr>(adaptor.getHead());
  auto s = dyn_cast_or_null<StringAttr>(adaptor.getTail());
  if (!c || !s)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_str_cons(static_cast<int32_t>(c.getInt()), scope.str(s)));
}

OpFoldResult StrFromCharOp::fold(FoldAdaptor adaptor) {
  auto c = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!c)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_str_from_char(static_cast<int32_t>(c.getInt())));
}

OpFoldResult StrShowOp::fold(FoldAdaptor adaptor) {
  Scope scope(getContext());
  if (auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue()))
    return scope.attr(idris_rt_str_show_f64(d.getValueAsDouble()));
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  int64_t value = extended(n, getIsSigned());
  return scope.attr(getIsSigned() ? idris_rt_str_show_s(value)
                                  : idris_rt_str_show_u(static_cast<uint64_t>(value)));
}

OpFoldResult StrSubstrOp::fold(FoldAdaptor adaptor) {
  auto s = dyn_cast_or_null<StringAttr>(adaptor.getStr());
  auto start = dyn_cast_or_null<IntegerAttr>(adaptor.getStart());
  auto length = dyn_cast_or_null<IntegerAttr>(adaptor.getLength());
  if (!s || !start || !length)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_str_substr(scope.str(s), start.getInt(), length.getInt()));
}

OpFoldResult StrReverseOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(idris_rt_str_reverse(s));
  });
}

// Nothing for the empty string: head and tail crash on it, so the op stays.
template <typename Fn>
OpFoldResult strNonEmpty(MLIRContext *ctx, Attribute operand, Fn fn) {
  return strUnary(ctx, operand, [&](Scope &scope, const idris_rt_str *s) -> OpFoldResult {
    if (idris_rt_str_length(s) == 0)
      return {};
    return fn(scope, s);
  });
}

OpFoldResult StrTailOp::fold(FoldAdaptor adaptor) {
  return strNonEmpty(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(idris_rt_str_tail(s));
  });
}

OpFoldResult StrLengthOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, idris_rt_str_length(s));
  });
}

OpFoldResult StrIndexOp::fold(FoldAdaptor adaptor) {
  auto i = dyn_cast_or_null<IntegerAttr>(adaptor.getIndex());
  if (!i)
    return {};
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(),
                  [&](Scope &, const idris_rt_str *s) -> OpFoldResult {
                    int64_t index = i.getInt();
                    if (index < 0 || index >= idris_rt_str_length(s))
                      return {};
                    return wrapped(type, idris_rt_str_index(s, index));
                  });
}

OpFoldResult StrHeadOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strNonEmpty(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, idris_rt_str_head(s));
  });
}

OpFoldResult StrCmpOp::fold(FoldAdaptor adaptor) {
  CmpPredicate predicate = getPredicate();
  MLIRContext *ctx = getContext();
  return strBinary(ctx, adaptor.getLhs(), adaptor.getRhs(),
                   [&](Scope &, const idris_rt_str *a, const idris_rt_str *b) {
                     return compared(ctx, predicate, idris_rt_str_cmp(a, b));
                   });
}

OpFoldResult StrToIntOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, idris_rt_str_to_int(s));
  });
}

OpFoldResult StrToDoubleOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return FloatAttr::get(type, idris_rt_str_to_double(s));
  });
}

} // namespace idr
