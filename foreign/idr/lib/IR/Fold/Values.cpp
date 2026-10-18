// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's results as constants: integers and comparisons, and the
// elements of a constant list.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"

using namespace mlir;

namespace idr::fold {

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

// The body says which constructor is the list's nil and which its cons, of
// an element and the rest. The walk goes from each cons to its rest, a part
// of the attribute it was read from, so it ends with the attribute.
std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  for (auto con = dyn_cast_or_null<ConAttr>(list); con;) {
    switch (kindOf(con.getCtor().role)) {
    case CtorRole::ListNil:
      return elements;
    case CtorRole::ListCons:
      break;
    case CtorRole::Plain:
    case CtorRole::Label:
    case CtorRole::Running:
    case CtorRole::Forced:
      return std::nullopt;
    }
    // A run along the rest is read cell by cell, which keeps a long list
    // linear to read: reading the rest as a field would build the run from
    // the next cell at each step. Every cell but the last holds the
    // element; the last holds the element and the rest.
    if (con.getSpine() == 1) {
      ArrayRef<ArrayAttr> cells = con.getCells();
      for (ArrayAttr cell : cells)
        elements.push_back(cell[0]);
      con = dyn_cast_or_null<ConAttr>(cells.back()[1]);
      continue;
    }
    // One cell, or a run along the element, whose first element is then a
    // list again; the rest is off the spine.
    elements.push_back(con.getField(0));
    con = dyn_cast_or_null<ConAttr>(con.getField(1));
  }
  return std::nullopt;
}

} // namespace idr::fold
