// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's attributes on other ops and on the arguments of functions:
// none. A fact a pass reads is an op's own property or a type, where no pass
// drops it silently, and a refusal is an op of the module. MLIR asks the
// dialect about every attribute named `idr.*`, so every such name is
// refused, not ignored; a name of no dialect is no business of ours.

#include "idr/IR/IdrDialect.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  return op->emitOpError("has an idr attribute, which no op carries: ") << attr.getName();
}

// A parameter's quantity and ownership are its type: the dialect marks no
// argument.
LogicalResult idr::IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned, unsigned,
                                                        NamedAttribute attr) {
  return op->emitOpError("has an idr argument attribute, which no argument carries: ")
         << attr.getName();
}
