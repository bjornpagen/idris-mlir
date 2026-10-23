// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's scalar operands and results as constants: integers by the
// kind the runtime takes or gives them in, Doubles, truths and orders; the
// attribute instance of the one fold; where idr.constant holds static data;
// and the string a constant list of characters packs to or a constant list
// of strings concatenates to.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Grades.h"
#include "idr/Support/Footprint.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::fold {

std::optional<APInt> integerOf(Attribute constant) {
  auto n = dyn_cast_or_null<IntegerAttr>(constant);
  if (!n)
    return std::nullopt;
  return n.getValue();
}

// A Double is an f64: a float of another width is no constant of the
// runtime's.
std::optional<double> realOf(Attribute constant) {
  auto d = dyn_cast_or_null<FloatAttr>(constant);
  if (!d || !d.getType().isF64())
    return std::nullopt;
  return d.getValueAsDouble();
}

APInt wrappedTo(Type type, int64_t value) {
  return APInt(type.getIntOrFloatBitWidth(), static_cast<uint64_t>(value), /*isSigned=*/false,
               /*implicitTrunc=*/true);
}

Attribute wrapped(Type type, int64_t value) {
  return IntegerAttr::get(type, wrappedTo(type, value));
}

// Each case of CmpPredicate is one test of the order's sign.
bool orderHolds(CmpPredicate predicate, int32_t order) {
  switch (predicate) {
  case CmpPredicate::eq:
    return order == 0;
  case CmpPredicate::lt:
    return order < 0;
  case CmpPredicate::lte:
    return order <= 0;
  case CmpPredicate::gt:
    return order > 0;
  case CmpPredicate::gte:
    return order >= 0;
  }
  return false;
}

Attribute ordered(MLIRContext *ctx, unsigned predicate, int32_t order) {
  return BoolAttr::get(ctx, orderHolds(static_cast<CmpPredicate>(predicate), order));
}

// Static data is used any number of times and, where its type holds
// references, held static: nothing frees it and no count writes it. A
// constant in its word has no cell for a count to write, so it stands at
// any hold.
bool constantStandsAt(Type type, Storage storage) {
  Grade grade = gradeOf(type);
  return grade.uses == Uses::Many &&
         (!grade.hold || storage == Storage::Word || grade.hold->release() == Release::Static);
}

//===----------------------------------------------------------------------===//
// The attribute instance
//===----------------------------------------------------------------------===//

// An integer of the op's result's integer type, a truth an i1's.
std::optional<Attribute> InAttributes::integer(Type type, const APInt &value) const {
  return IntegerAttr::get(type, value);
}

std::optional<Attribute> InAttributes::real(Type type, double value) const {
  return FloatAttr::get(type, value);
}

// The scope keeps what the runtime made, whether or not idr.constant holds
// it at the result's type.
std::optional<Attribute> InAttributes::str(Type type, const idris_rt_str *made) {
  scope.keep(made);
  Attribute constant = held(strAttr(scope.context(), made), type);
  return constant ? std::optional(constant) : std::nullopt;
}

std::optional<Attribute> InAttributes::big(Type type, idris_rt_big made) {
  scope.keep(made);
  Attribute constant = held(bigAttr(scope.context(), made), type);
  return constant ? std::optional(constant) : std::nullopt;
}

//===----------------------------------------------------------------------===//
// Constant lists
//===----------------------------------------------------------------------===//

namespace {

// The elements of a constant list: a chain of its type's cons cells ending
// in its nil; nothing for any other constant. A list is a family whose
// shape is base's list, a constructor with no field and one of an element
// and the list, which the family's declaration says (its ListShape), so
// the walk reads no role and no name. It goes from each cons to its rest,
// a part of the attribute it was read from, so it ends. A list is as long
// as the program's text makes it.
std::optional<footprint::Vector<Attribute>> listElements(Attribute list) {
  footprint::Vector<Attribute> elements;
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

} // namespace

// The runtime packs a list of characters as the cons of each onto the rest,
// from the empty string, and concatenates a list of strings as the append
// of each, in order: the functions of str.cons and str.append. Which one is
// the elements' kind: a verified constant holds each at the list's element
// type. Each step's scope holds the string before it and the element's
// own, released once the next string is made from them, which the runtime
// makes fresh: a fold holds a fixed number of references however long the
// list. The last string is kept by the attribute that copies it.
Attribute stringOfList(MLIRContext *ctx, Attribute list) {
  std::optional<footprint::Vector<Attribute>> elements = listElements(list);
  if (!elements)
    return {};
  const idris_rt_str *s = idris_rt_str_from_utf8("", 0);
  if (llvm::any_of(*elements, [](Attribute e) { return isa<StringAttr>(e); })) {
    for (Attribute piece : *elements) {
      Scope step(ctx);
      step.keep(s);
      std::optional<const idris_rt_str *> p = strOf(step, piece);
      if (!p)
        return {};
      s = runtime::Abi<StrAppendOp>::function(s, *p);
    }
  } else {
    for (Attribute c : llvm::reverse(*elements)) {
      Scope step(ctx);
      step.keep(s);
      std::optional<APInt> ch = integerOf(c);
      if (!ch)
        return {};
      s = runtime::Abi<StrConsOp>::function(static_cast<int32_t>(ch->getSExtValue()), s);
    }
  }
  Scope scope(ctx);
  scope.keep(s);
  return strAttr(ctx, s);
}

} // namespace idr::fold
