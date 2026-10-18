// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's attributes on other ops and on the arguments of functions:
// none that a pass reads. A fact a pass reads is an op's own property or a
// type, where no pass drops it silently. MLIR asks the dialect about every
// attribute named `idr.*`, so every such name is refused, not ignored; a
// name of no dialect is no business of ours. The one the dialect declares,
// `idr.refusals` (IdrBase.td), is the frontend's report to the driver, not a
// fact of the program: the refusals it found, which the driver re-emits and
// no pass reads, held by the module it writes.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::IdrDialect::verifyOperationAttribute(Operation *op, NamedAttribute attr) {
  if (attr.getName() != getRefusalsAttrHelper().getName())
    return op->emitOpError("has an unknown idr attribute ") << attr.getName();
  auto refusals = dyn_cast<ArrayAttr>(attr.getValue());
  if (isa<ModuleOp>(op) && !op->getParentOp() && refusals &&
      llvm::all_of(refusals, llvm::IsaPred<RefusalAttr>))
    return success();
  return op->emitOpError("has ") << attr.getName()
                                 << ", which is an array of #idr.refusal on the top-level module "
                                    "alone";
}

// A parameter's quantity and ownership are its type: the dialect marks no
// argument.
LogicalResult idr::IdrDialect::verifyRegionArgAttribute(Operation *op, unsigned, unsigned,
                                                        NamedAttribute attr) {
  return op->emitOpError("has an unknown idr argument attribute ") << attr.getName();
}
