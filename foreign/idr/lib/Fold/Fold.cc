// The folders of the string and big ops, and of double_head and int_head:
// each converts its constant operands to runtime values, calls the runtime's
// own C function, which idris-mlir-cc links natively, and converts the
// result back. A primitive has one implementation, at compile time and at
// runtime; nothing here computes one. An op whose operands would make it
// crash is not folded: it crashes at runtime.

#include "idr/Idr.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr {

namespace {

// The owned references one fold holds, released together when it ends.
// Every runtime operation returns an owned reference, even when what it
// returns is one of its arguments (appending the empty string gives the
// other argument, with one more reference), so the scope keeps every
// reference it is given, a repeated one as often as it was given, and
// releases each once.
class Scope {
public:
  explicit Scope(MLIRContext *c) : ctx(c) {}
  ~Scope() {
    for (const idris_rt_str *s : strings)
      idris_rt_str_release(s);
    for (idris_rt_big b : bigs)
      idris_rt_big_release(b);
  }
  Scope(const Scope &) = delete;
  Scope &operator=(const Scope &) = delete;

  const idris_rt_str *str(StringAttr value) {
    return keep(idris_rt_str_from_utf8(value.data(), value.size()));
  }
  idris_rt_big big(BigAttr value) {
    return keep(idris_rt_big_from_str(str(StringAttr::get(ctx, value.getValue()))));
  }
  const idris_rt_str *keep(const idris_rt_str *s) {
    strings.push_back(s);
    return s;
  }
  idris_rt_big keep(idris_rt_big b) {
    bigs.push_back(b);
    return b;
  }
  Attribute attr(const idris_rt_str *s) {
    keep(s);
    return StringAttr::get(ctx, StringRef(idris_rt_str_bytes(s), s->bytes));
  }
  Attribute attr(idris_rt_big b) {
    keep(b);
    const idris_rt_str *text = keep(idris_rt_big_show(b));
    return BigAttr::get(ctx, StringRef(idris_rt_str_bytes(text), text->bytes));
  }

private:
  MLIRContext *ctx;
  SmallVector<const idris_rt_str *> strings;
  SmallVector<idris_rt_big> bigs;
};

// The 64-bit value of an integer operand, extended as the op's signedness
// says.
int64_t extended(IntegerAttr value, bool isSigned) {
  return isSigned ? value.getValue().getSExtValue()
                  : static_cast<int64_t>(value.getValue().getZExtValue());
}

// A runtime result modulo 2^64 as an integer of `type`.
Attribute wrapped(Type type, int64_t value) {
  unsigned width = type.getIntOrFloatBitWidth();
  return IntegerAttr::get(type, APInt(width, static_cast<uint64_t>(value), /*isSigned=*/false,
                                      /*implicitTrunc=*/true));
}

Attribute compared(MLIRContext *ctx, CmpPredicate predicate, int32_t order) {
  bool holds = false;
  switch (predicate) {
  case CmpPredicate::eq:
    holds = order == 0;
    break;
  case CmpPredicate::lt:
    holds = order < 0;
    break;
  case CmpPredicate::lte:
    holds = order <= 0;
    break;
  case CmpPredicate::gt:
    holds = order > 0;
    break;
  case CmpPredicate::gte:
    holds = order >= 0;
    break;
  }
  return BoolAttr::get(ctx, holds);
}

template <typename Fn> OpFoldResult strUnary(MLIRContext *ctx, Attribute operand, Fn fn) {
  auto s = dyn_cast_or_null<StringAttr>(operand);
  if (!s)
    return {};
  Scope scope(ctx);
  return fn(scope, scope.str(s));
}

using BigOp = idris_rt_big (*)(idris_rt_big, idris_rt_big);

OpFoldResult bigBinary(MLIRContext *ctx, Attribute lhs, Attribute rhs, BigOp op) {
  auto a = dyn_cast_or_null<BigAttr>(lhs), b = dyn_cast_or_null<BigAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  return scope.attr(op(scope.big(a), scope.big(b)));
}

// Division by zero crashes; the runtime's zero is the word 1.
OpFoldResult bigDivision(MLIRContext *ctx, Attribute lhs, Attribute rhs, BigOp op) {
  auto a = dyn_cast_or_null<BigAttr>(lhs), b = dyn_cast_or_null<BigAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  idris_rt_big divisor = scope.big(b);
  if (idris_rt_big_cmp(divisor, scope.keep(idris_rt_big_from_int_s(0))) == 0)
    return {};
  return scope.attr(op(scope.big(a), divisor));
}

} // namespace

OpFoldResult StrAppendOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<StringAttr>(adaptor.getLhs());
  auto b = dyn_cast_or_null<StringAttr>(adaptor.getRhs());
  if (!a || !b)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_str_append(scope.str(a), scope.str(b)));
}

OpFoldResult StrConsOp::fold(FoldAdaptor adaptor) {
  auto c = dyn_cast_or_null<IntegerAttr>(adaptor.getHead());
  auto s = dyn_cast_or_null<StringAttr>(adaptor.getTail());
  if (!c || !s)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_str_cons(static_cast<int32_t>(c.getInt()), scope.str(s)));
}

// The elements of a constant list: a chain of constructors of two fields
// ending in one of none; nothing for any other constant.
std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  while (true) {
    auto con = dyn_cast_or_null<ConAttr>(list);
    if (!con)
      return std::nullopt;
    ArrayAttr fields = con.getFields();
    if (fields.empty())
      return elements;
    if (fields.size() != 2)
      return std::nullopt;
    elements.push_back(fields[0]);
    list = fields[1];
  }
}

OpFoldResult StrPackOp::fold(FoldAdaptor adaptor) {
  std::optional<SmallVector<Attribute>> chars = listElements(adaptor.getList());
  if (!chars || !llvm::all_of(*chars, [](Attribute c) { return isa<IntegerAttr>(c); }))
    return {};
  Scope scope(getContext());
  const idris_rt_str *s = scope.str(StringAttr::get(getContext(), ""));
  for (Attribute c : llvm::reverse(*chars))
    s = scope.keep(idris_rt_str_cons(static_cast<int32_t>(cast<IntegerAttr>(c).getInt()), s));
  return scope.attr(s);
}

OpFoldResult StrConcatOp::fold(FoldAdaptor adaptor) {
  std::optional<SmallVector<Attribute>> parts = listElements(adaptor.getList());
  if (!parts || !llvm::all_of(*parts, [](Attribute p) { return isa<StringAttr>(p); }))
    return {};
  Scope scope(getContext());
  const idris_rt_str *s = scope.str(StringAttr::get(getContext(), ""));
  for (Attribute p : *parts)
    s = scope.keep(idris_rt_str_append(s, scope.str(cast<StringAttr>(p))));
  return scope.attr(s);
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

OpFoldResult StrTailOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(),
                  [](Scope &scope, const idris_rt_str *s) -> OpFoldResult {
                    if (idris_rt_str_length(s) == 0)
                      return {};
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
  return strUnary(getContext(), adaptor.getStr(),
                  [&](Scope &, const idris_rt_str *s) -> OpFoldResult {
                    if (idris_rt_str_length(s) == 0)
                      return {};
                    return wrapped(type, idris_rt_str_head(s));
                  });
}

OpFoldResult StrCmpOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<StringAttr>(adaptor.getLhs());
  auto b = dyn_cast_or_null<StringAttr>(adaptor.getRhs());
  if (!a || !b)
    return {};
  Scope scope(getContext());
  return compared(getContext(), getPredicate(), idris_rt_str_cmp(scope.str(a), scope.str(b)));
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
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_big_neg(scope.big(a)));
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
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_nat_from_big(scope.big(a)));
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
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return FloatAttr::get(getType(), idris_rt_big_to_double(scope.big(a)));
}

OpFoldResult BigShowOp::fold(FoldAdaptor adaptor) {
  auto a = dyn_cast_or_null<BigAttr>(adaptor.getValue());
  if (!a)
    return {};
  Scope scope(getContext());
  return scope.attr(idris_rt_big_show(scope.big(a)));
}

OpFoldResult BigFromStrOp::fold(FoldAdaptor adaptor) {
  return strUnary(getContext(), adaptor.getStr(), [](Scope &scope, const idris_rt_str *s) {
    return scope.attr(idris_rt_big_from_str(s));
  });
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
