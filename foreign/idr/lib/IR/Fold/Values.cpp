// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's scalar operands and results as constants: integers by the
// kind the runtime takes or gives them in, Doubles, truths and orders; the
// attribute instance of the one fold; and where idr.constant holds static
// data.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"

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

} // namespace idr::fold
