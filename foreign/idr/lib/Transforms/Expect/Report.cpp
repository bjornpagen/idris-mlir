// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How a property reports where it fails.

#include "idr/Transforms/Expect.h"

using namespace mlir;

namespace idr::expect {

InFlightDiagnostic fail(Location loc, StringRef property) {
  return emitError(loc) << "expected " << property << ": ";
}

// Any function: before lowering an idr.func, after it a func.func or an
// llvm.func.
std::string where(Operation *op) {
  auto fn = dyn_cast<FunctionOpInterface>(op);
  if (!fn)
    fn = op->getParentOfType<FunctionOpInterface>();
  return fn ? ("@" + SymbolTable::getSymbolName(fn).getValue()).str() : std::string("the module");
}

} // namespace idr::expect
