// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folders of the string ops: each calls the runtime's function of its
// op on its constant operands, as Fold.h says. Then the string a constant
// list of characters packs to, or a constant list of strings concatenates
// to, which the folders of idr.str.pack and idr.str.concat are. Last the
// folders of double_head and int_head: the head of a number is the first
// character of its text, a fact about the string the runtime shows it as,
// so they fold beside the string ops.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

using fold::compared;
using fold::listElements;
using fold::Scope;
using fold::strBinary;
using fold::strUnary;
using fold::wrapped;

OpFoldResult StrAppendOp::fold(FoldAdaptor adaptor) {
  return strBinary(getContext(), adaptor.getLhs(), adaptor.getRhs(),
                   [](Scope &scope, const idris_rt_str *a, const idris_rt_str *b) {
                     return scope.attr(fold::runtime<StrAppendOp>(a, b));
                   });
}

OpFoldResult StrConsOp::fold(FoldAdaptor adaptor) {
  auto c = dyn_cast_or_null<IntegerAttr>(adaptor.getHead());
  auto s = dyn_cast_or_null<StringAttr>(adaptor.getTail());
  if (!c || !s)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrConsOp>(static_cast<int32_t>(c.getInt()), scope.str(s)));
}

OpFoldResult StrFromCharOp::fold(FoldAdaptor adaptor) {
  auto c = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!c)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrFromCharOp>(static_cast<int32_t>(c.getInt())));
}

// The text of a number by the op's own function: an integer extended to the
// function's word as the op reads it, sign-extended when signed and
// zero-extended when not.
OpFoldResult StrShowSIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrShowSIntOp>(n.getValue().getSExtValue()));
}

OpFoldResult StrShowUIntOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrShowUIntOp>(n.getValue().getZExtValue()));
}

OpFoldResult StrShowDoubleOp::fold(FoldAdaptor adaptor) {
  auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!d)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrShowDoubleOp>(d.getValueAsDouble()));
}

OpFoldResult StrSubstrOp::fold(FoldAdaptor adaptor) {
  auto s = dyn_cast_or_null<StringAttr>(adaptor.getStr());
  auto start = dyn_cast_or_null<IntegerAttr>(adaptor.getStart());
  auto length = dyn_cast_or_null<IntegerAttr>(adaptor.getLength());
  if (!s || !start || !length)
    return {};
  Scope scope(getContext());
  return scope.attr(fold::runtime<StrSubstrOp>(scope.str(s), start.getInt(), length.getInt()));
}

OpFoldResult StrReverseOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(fold::runtime<StrReverseOp>(s));
  });
}

// Nothing for a string the guard refuses, the empty one: the program never
// takes its tail, since the guard crashes first.
OpFoldResult StrTailOp::fold(FoldAdaptor adaptor) {
  if (!guardHolds(adaptor))
    return {};
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(fold::runtime<StrTailOp>(s));
  });
}

OpFoldResult StrLengthOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrLengthOp>(s));
  });
}

OpFoldResult StrBytesLengthOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrBytesLengthOp>(s));
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
                       return wrapped(type, fold::runtime<StrScalarAtOp>(s, at));
                     });
}

OpFoldResult StrDropBytesOp::fold(FoldAdaptor adaptor) {
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [](Scope &scope, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return scope.attr(fold::runtime<StrDropBytesOp>(s, at));
                     });
}

OpFoldResult StrScalarBytesOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!value)
    return {};
  return wrapped(getType(), fold::runtime<StrScalarBytesOp>(static_cast<int32_t>(value.getInt())));
}

// Nothing at an index the guard refuses, outside the string, where the
// program never reads.
OpFoldResult StrIndexOp::fold(FoldAdaptor adaptor) {
  if (!guardHolds(adaptor))
    return {};
  Type type = getType();
  int64_t at = cast<IntegerAttr>(adaptor.getIndex()).getInt();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrIndexOp>(s, at));
  });
}

// The head of a str.cons is the character it put first, read on the cons's
// string or through the guard that it is not empty, which Emit puts before
// a head and which folds away on a cons. Otherwise nothing for a string the
// guard refuses, the empty one: the program never takes its head, since the
// guard crashes first.
OpFoldResult StrHeadOp::fold(FoldAdaptor adaptor) {
  Value str = getStr();
  if (auto guard = str.getDefiningOp<CheckNonemptyOp>())
    str = guard.getStr();
  if (auto cons = str.getDefiningOp<StrConsOp>())
    return cons.getHead();
  if (!guardHolds(adaptor))
    return {};
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrHeadOp>(s));
  });
}

OpFoldResult StrCmpOp::fold(FoldAdaptor adaptor) {
  CmpPredicate predicate = getPredicate();
  MLIRContext *ctx = getContext();
  return strBinary(ctx, adaptor.getLhs(), adaptor.getRhs(),
                   [&](Scope &, const idris_rt_str *a, const idris_rt_str *b) {
                     return compared(ctx, predicate, fold::runtime<StrCmpOp>(a, b));
                   });
}

OpFoldResult StrToIntOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrToIntOp>(s));
  });
}

OpFoldResult StrToDoubleOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return FloatAttr::get(type, fold::runtime<StrToDoubleOp>(s));
  });
}

// The runtime packs a list of characters as the cons of each onto the rest,
// from the empty string, and concatenates a list of strings as the append
// of each, in order: the functions of str.cons and str.append. The list's
// type says which: its element is a character or a string, and a verified
// constant holds each element at that type.
Attribute stringOfList(MLIRContext *ctx, Attribute list) {
  std::optional<SmallVector<Attribute>> elements = listElements(list);
  if (!elements)
    return {};
  Scope scope(ctx);
  // Each string is kept once the next is made from it; the last is the
  // attribute's, which keeps it.
  const idris_rt_str *s = idris_rt_str_from_utf8("", 0);
  auto step = [&](const idris_rt_str *next) {
    scope.keep(s);
    s = next;
  };
  if (isa<StrType>(unrestricted(cast<ConAttr>(list).getData().getListElement()))) {
    for (Attribute p : *elements)
      step(fold::runtime<StrAppendOp>(s, scope.str(cast<StringAttr>(p))));
    return scope.attr(s);
  }
  for (Attribute c : llvm::reverse(*elements))
    step(fold::runtime<StrConsOp>(static_cast<int32_t>(cast<IntegerAttr>(c).getInt()), s));
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
  return wrapped(getType(), fold::runtime<DoubleHeadOp>(d.getValueAsDouble()));
}

// The head of an integer's text, by the op's own function, as show_sint and
// show_uint extend it.
OpFoldResult IntHeadSOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  return wrapped(getType(), fold::runtime<IntHeadSOp>(n.getValue().getSExtValue()));
}

OpFoldResult IntHeadUOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  return wrapped(getType(), fold::runtime<IntHeadUOp>(n.getValue().getZExtValue()));
}

} // namespace idr
