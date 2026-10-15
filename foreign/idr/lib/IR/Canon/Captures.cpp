// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants a constructor, a closure or a suspension folds with: what a
// constant holds in a field or capture of that type.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"

using namespace mlir;
using namespace idr;

namespace idr::canon {

// A field or capture of a constant holds a word or a Double of exactly its
// type, or a value idr.constant holds at it. An array is neither: a dense
// tensor is a value of its own, which arith.constant builds and no constant
// constructor holds, so a constructor around one stays an op.
bool buildable(Attribute value, Type type) {
  if (isa<IntegerAttr, FloatAttr>(value))
    return cast<TypedAttr>(value).getType() == type && isFieldType(type);
  return ConstantOp::isBuildableWith(value, type);
}

} // namespace idr::canon
