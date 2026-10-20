// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a tagged action prints, out of the template so that every action
// shares one definition.

#include "idr/Support/Actions.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Unit.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

// The symbol the unit's op is, or is nested in: the function an action's
// work is attributed to.
static Operation *symbolOf(const IRUnit &unit) {
  auto *op = llvm::dyn_cast_if_present<Operation *>(unit);
  for (; op; op = op->getParentOp())
    if (op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
      return op;
  return nullptr;
}

void idr::support::printTag(llvm::raw_ostream &os, llvm::StringRef tag, ArrayRef<IRUnit> units) {
  os << '`' << tag << '`';
  for (const IRUnit &unit : units)
    if (Operation *symbol = symbolOf(unit))
      os << " @" << SymbolTable::getSymbolName(symbol).getValue();
}
