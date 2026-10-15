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
LogicalResult notCalled(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "not-called";
  StringRef f = function.ltrim('@');
  if (f.empty())
    return fail(module.getLoc(), property) << "name the function, as not-called=@f";
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  module.walk([&](CallOp call) {
    auto callee = symbols.lookup<FunctionOpInterface>(call.getCalleeAttr().getAttr());
    if (call.getCallee() != f && !(callee && names(callee, f)))
      return;
    fail(call.getLoc(), property) << function << " is still called, as @" << call.getCallee()
                                  << ", in " << where(call);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
