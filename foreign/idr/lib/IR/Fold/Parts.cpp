// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The attribute place of the composite folds (FoldParts.h): a constant
// constructor's cells and fields as the attribute holds them, and a
// constructor made of attributes, where idr.constant holds it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/FoldParts.h"

#include "mlir/IR/BuiltinAttributes.h"

using namespace mlir;

namespace idr::fold {

std::optional<RunCell> InParts::cellOf(Attribute constant) const {
  auto con = dyn_cast_or_null<ConAttr>(constant);
  return con ? std::optional<RunCell>(RunCell{con, 0}) : std::nullopt;
}

// MLIR's folding drivers materialize the attribute at the result's type,
// which a field read is of: the field's own constant.
std::optional<Attribute> InParts::fieldOf(Attribute constant, unsigned index, Type) const {
  auto con = dyn_cast_or_null<ConAttr>(constant);
  return con ? std::optional<Attribute>(con.getField(index)) : std::nullopt;
}

std::optional<Attribute> InParts::constructor(Type type, const DataType &data,
                                              ArrayRef<Attribute> fields) const {
  Attribute made = held(ConAttr::get(context, data, ArrayAttr::get(context, fields)), type);
  return made ? std::optional(made) : std::nullopt;
}

std::optional<Attribute> InParts::same(Type type, Attribute constant) const {
  Attribute made = held(constant, type);
  return made ? std::optional(made) : std::nullopt;
}

} // namespace idr::fold
