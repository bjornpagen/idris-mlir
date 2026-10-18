// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// not-called: no call of a function, or of a copy of it, is left: each
// became what it computes, as a call of a function that gives back its
// argument becomes the argument. Which pass did it, and whether the
// function is still in the module for something else that names it, are
// the passes' business; that no call is left is the property.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// A function the module never had is not called either, so a test states
// the property of a function its emitted module calls.
LogicalResult notCalled(const Request<Symbol> &request) {
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  request.module->walk([&](CallOp call) {
    if (!callsNamed(call, request.argument, symbols))
      return;
    fail(call.getLoc(), request.property) << "@" << request.argument.name
                                          << " is still called, as @" << call.getCallee() << ", in "
                                          << where(call);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
