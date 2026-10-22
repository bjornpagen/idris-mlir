// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's scalar operands and results as constants: integers by the
// kind the runtime takes or gives them in, Doubles, truths and orders; and
// the elements of a constant list, with the string a list of characters
// packs to or a list of strings concatenates to.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::fold {

// An integer constant read as the kind says: as its 32-bit word, its 64-bit
// one, or extended to 64 bits with its sign or with zeros, as the op's
// signedness extends it for its function.
std::optional<int32_t> int32Of(Attribute constant) {
  auto n = dyn_cast_or_null<IntegerAttr>(constant);
  if (!n)
    return std::nullopt;
  return static_cast<int32_t>(n.getValue().getSExtValue());
}

std::optional<int64_t> int64Of(Attribute constant) {
  auto n = dyn_cast_or_null<IntegerAttr>(constant);
  if (!n)
    return std::nullopt;
  return n.getValue().getSExtValue();
}

std::optional<int64_t> signedOf(Attribute constant) { return int64Of(constant); }

std::optional<uint64_t> unsignedOf(Attribute constant) {
  auto n = dyn_cast_or_null<IntegerAttr>(constant);
  if (!n)
    return std::nullopt;
  return n.getValue().getZExtValue();
}

std::optional<double> doubleOf(Attribute constant) {
  auto d = dyn_cast_or_null<FloatAttr>(constant);
  if (!d)
    return std::nullopt;
  return d.getValueAsDouble();
}

Attribute intAttr(Type type, int64_t value) { return wrapped(type, value); }

Attribute wrapped(Type type, int64_t value) {
  unsigned width = type.getIntOrFloatBitWidth();
  return IntegerAttr::get(type, APInt(width, static_cast<uint64_t>(value), /*isSigned=*/false,
                                      /*implicitTrunc=*/true));
}

Attribute doubleAttr(Type type, double value) { return FloatAttr::get(type, value); }

Attribute boolAttr(MLIRContext *ctx, bool value) { return BoolAttr::get(ctx, value); }

// The order a comparison's runtime function gives, against the predicate
// the op holds: each case of CmpPredicate one test of the order's sign.
Attribute ordered(MLIRContext *ctx, unsigned predicate, int32_t order) {
  bool holds = false;
  switch (static_cast<CmpPredicate>(predicate)) {
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

// A list is a family whose shape is base's list, a constructor with no
// field and one of an element and the list, which the family's declaration
// says (its ListShape), so the walk reads no role and no name. It goes from
// each cons to its rest, a part of the attribute it was read from, so it
// ends.
std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  for (auto con = dyn_cast_or_null<ConAttr>(list); con;) {
    std::optional<families::ListShape> shape = con.getData().listShape();
    if (!shape)
      return std::nullopt;
    if (con.getTag() == shape->nil)
      return elements;
    elements.push_back(con.getField(shape->element));
    con = dyn_cast_or_null<ConAttr>(con.getField(1 - shape->element));
  }
  return std::nullopt;
}

// The runtime packs a list of characters as the cons of each onto the rest,
// from the empty string, and concatenates a list of strings as the append
// of each, in order: the functions of str.cons and str.append. Which one is
// the elements' kind: a verified constant holds each at the list's element
// type. Each string is kept once the next is made from it, the last by the
// attribute that copies it.
Attribute stringOfList(MLIRContext *ctx, Attribute list) {
  std::optional<SmallVector<Attribute>> elements = listElements(list);
  if (!elements)
    return {};
  Scope scope(ctx);
  const idris_rt_str *s = idris_rt_str_from_utf8("", 0);
  auto step = [&](const idris_rt_str *next) {
    scope.keep(s);
    s = next;
  };
  if (llvm::any_of(*elements, [](Attribute e) { return isa<StringAttr>(e); })) {
    for (Attribute piece : *elements) {
      std::optional<const idris_rt_str *> p = strOf(scope, piece);
      if (!p) {
        scope.keep(s);
        return {};
      }
      step(runtime::Abi<StrAppendOp>::function(s, *p));
    }
    return strAttr(scope, s);
  }
  for (Attribute c : llvm::reverse(*elements)) {
    std::optional<int32_t> ch = int32Of(c);
    if (!ch) {
      scope.keep(s);
      return {};
    }
    step(runtime::Abi<StrConsOp>::function(*ch, s));
  }
  return strAttr(scope, s);
}

} // namespace idr::fold
