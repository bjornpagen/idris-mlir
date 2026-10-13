// The folders of the string ops: each calls the runtime's own C function on
// its constant operands, as Fold.h says. Then the string a constant list of
// characters packs to, or a constant list of strings concatenates to, which
// the folders of idr.str.pack and idr.str.concat are. Last the folders of
// double_head and int_head: the head of a number is the first character of
// its text, a fact about the string the runtime shows it as, so they fold
// beside the string ops.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "idris_rt.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

using fold::compared;
using fold::extended;
using fold::listElements;
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

namespace {

// Nothing for a string the guard of head and tail refuses, the empty one:
// the program never takes its head or tail, since the guard crashes first.
template <typename Fn>
OpFoldResult strNonEmpty(MLIRContext *ctx, Attribute operand, Fn fn) {
  if (!checkHolds(CheckKind::Nonempty, operand))
    return {};
  return strUnary(ctx, operand, fn);
}

} // namespace

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

OpFoldResult StrBytesLengthOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, idris_rt_str_bytes_length(s));
  });
}

namespace {

// `fn` of a constant string and a constant byte offset. Every offset has a
// meaning, so there is no guard to consult.
template <typename Fn>
OpFoldResult strAtOffset(MLIRContext *ctx, Attribute str, Attribute offset, Fn fn) {
  auto at = dyn_cast_or_null<IntegerAttr>(offset);
  if (!at)
    return {};
  return strUnary(ctx, str, [&](Scope &scope, const idris_rt_str *s) -> OpFoldResult {
    return fn(scope, s, at.getInt());
  });
}

} // namespace

OpFoldResult StrScalarAtOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [&](Scope &, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return wrapped(type, idris_rt_str_scalar_at(s, at));
                     });
}

OpFoldResult StrScalarEndOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [&](Scope &, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return wrapped(type, idris_rt_str_scalar_end(s, at));
                     });
}

OpFoldResult StrDropBytesOp::fold(FoldAdaptor adaptor) {
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [](Scope &scope, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return scope.attr(idris_rt_str_drop_bytes(s, at));
                     });
}

// Nothing at an index the guard refuses, outside the string, where the
// program never reads.
OpFoldResult StrIndexOp::fold(FoldAdaptor adaptor) {
  Attribute index = adaptor.getIndex();
  Type type = getType(), word = getIndex().getType();
  return strUnary(getContext(), adaptor.getStr(),
                  [&](Scope &, const idris_rt_str *s) -> OpFoldResult {
                    Attribute length = wrapped(word, idris_rt_str_length(s));
                    if (!checkHolds(CheckKind::InBounds, {index, length}))
                      return {};
                    return wrapped(type, idris_rt_str_index(s, cast<IntegerAttr>(index).getInt()));
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

Attribute stringOfList(MLIRContext *ctx, Attribute list) {
  std::optional<SmallVector<Attribute>> elements = listElements(list);
  if (!elements)
    return {};
  Scope scope(ctx);
  const idris_rt_str *s = scope.str(StringAttr::get(ctx, ""));
  if (llvm::all_of(*elements, [](Attribute c) { return isa<IntegerAttr>(c); })) {
    for (Attribute c : llvm::reverse(*elements))
      s = scope.keep(idris_rt_str_cons(static_cast<int32_t>(cast<IntegerAttr>(c).getInt()), s));
    return scope.attr(s);
  }
  if (!llvm::all_of(*elements, [](Attribute p) { return isa<StringAttr>(p); }))
    return {};
  for (Attribute p : *elements)
    s = scope.keep(idris_rt_str_append(s, scope.str(cast<StringAttr>(p))));
  return scope.attr(s);
}

OpFoldResult StrPackOp::fold(FoldAdaptor adaptor) {
  return stringOfList(getContext(), adaptor.getList());
}

OpFoldResult StrConcatOp::fold(FoldAdaptor adaptor) {
  return stringOfList(getContext(), adaptor.getList());
}

OpFoldResult DoubleHeadOp::fold(FoldAdaptor adaptor) {
  auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!d)
    return {};
  return wrapped(getType(), idris_rt_double_head(d.getValueAsDouble()));
}

OpFoldResult IntHeadOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  int64_t value = extended(n, getIsSigned());
  return wrapped(getType(), getIsSigned() ? idris_rt_int_head_s(value)
                                          : idris_rt_int_head_u(static_cast<uint64_t>(value)));
}

} // namespace idr
