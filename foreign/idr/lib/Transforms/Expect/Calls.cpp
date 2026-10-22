// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// calls: a function still calls another, by upstream's call interface, so
// it is stated the same of the program's calls before lowering and of the
// LLVM dialect's after it, where the callee may be a function of the
// runtime, named by its symbol.

#include "Checks.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

namespace idr::expect {

// Some call in a copy of @f calls @g or a copy of it.
LogicalResult calls(const Request<Pair> &request) {
  const Pair &pair = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  for (FunctionOpInterface fn : pair.caller.functions) {
    WalkResult found = fn->walk([&](CallOpInterface call) {
      return callsNamed(call, pair.callee, symbols) ? WalkResult::interrupt()
                                                    : WalkResult::advance();
    });
    if (found.wasInterrupted())
      return success();
  }
  return fail(pair.caller.functions.front()->getLoc(), request.property)
         << "@" << pair.caller.name << " calls no @" << pair.callee.name;
}

} // namespace idr::expect
