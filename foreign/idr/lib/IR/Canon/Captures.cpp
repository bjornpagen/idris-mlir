// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants a constructor, a closure or a suspension folds with: those
// the dialect builds at the type of the field or capture they fill.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Arith/IR/Arith.h"

using namespace mlir;
using namespace idr;

namespace idr::canon {

bool buildable(Attribute value, Type type) {
  return ConstantOp::isBuildableWith(value, unrestricted(type)) ||
         arith::ConstantOp::isBuildableWith(value, unrestricted(type));
}

} // namespace idr::canon
