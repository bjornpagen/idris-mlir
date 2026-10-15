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
using fold::runtimeOfWord;
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

// A Double, or an integer as the op reads it: the op has a function of the
// runtime for each.
OpFoldResult StrShowOp::fold(FoldAdaptor adaptor) {
  if (auto d = dyn_cast_or_null<FloatAttr>(adaptor.getValue())) {
    Scope scope(getContext());
    return scope.attr(runtime::Abi<StrShowOp>::doubleFunction(d.getValueAsDouble()));
  }
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  Scope scope(getContext());
  return scope.attr(runtimeOfWord<StrShowOp>(n, getIsSigned()));
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

namespace {

// Nothing for a string the guard of head and tail refuses, the empty one:
// the program never takes its head or tail, since the guard crashes first.
template <typename Fn>
OpFoldResult strNonEmpty(MLIRContext *ctx, Attribute operand, Fn fn) {
  if (!CheckNonemptyOp::holds({operand}))
    return {};
  return strUnary(ctx, operand, fn);
}

} // namespace

OpFoldResult StrTailOp::fold(FoldAdaptor adaptor) {
  return strNonEmpty(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
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

OpFoldResult StrScalarEndOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [&](Scope &, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return wrapped(type, fold::runtime<StrScalarEndOp>(s, at));
                     });
}

OpFoldResult StrDropBytesOp::fold(FoldAdaptor adaptor) {
  return strAtOffset(getContext(), adaptor.getStr(), adaptor.getOffset(),
                     [](Scope &scope, const idris_rt_str *s, int64_t at) -> OpFoldResult {
                       return scope.attr(fold::runtime<StrDropBytesOp>(s, at));
                     });
}

// Nothing at an index the guard refuses, outside the string, where the
// program never reads.
OpFoldResult StrIndexOp::fold(FoldAdaptor adaptor) {
  Attribute index = adaptor.getIndex();
  if (!CheckInBoundsOp::holds({index, adaptor.getStr()}))
    return {};
  Type type = getType();
  int64_t at = cast<IntegerAttr>(index).getInt();
  return strUnary(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
    return wrapped(type, fold::runtime<StrIndexOp>(s, at));
  });
}

OpFoldResult StrHeadOp::fold(FoldAdaptor adaptor) {
  Type type = getType();
  return strNonEmpty(getContext(), adaptor.getStr(), [&](Scope &, const idris_rt_str *s) {
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
  const idris_rt_str *s = scope.str(StringAttr::get(ctx, ""));
  if (isa<StrType>(unrestricted(cast<ConAttr>(list).getData().getListElement()))) {
    for (Attribute p : *elements)
      s = scope.keep(fold::runtime<StrAppendOp>(s, scope.str(cast<StringAttr>(p))));
    return scope.attr(s);
  }
  for (Attribute c : llvm::reverse(*elements))
    s = scope.keep(fold::runtime<StrConsOp>(static_cast<int32_t>(cast<IntegerAttr>(c).getInt()), s));
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

OpFoldResult IntHeadOp::fold(FoldAdaptor adaptor) {
  auto n = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!n)
    return {};
  return wrapped(getType(), runtimeOfWord<IntHeadOp>(n, getIsSigned()));
}

} // namespace idr
