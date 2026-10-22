// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reaches: a function's code reaches another's through the functions its
// body names, whatever names them: a call, a dispatch's call of a label, a
// constant. That a run of one may run the other is a fact of the call
// graph, which is complete once every force is a call; which function
// stands between them is the passes' business.

#include "idr/Transforms/Expect.h"


#include "llvm/ADT/STLExtras.h"

#include <optional>

using namespace mlir;

namespace idr::expect {

// `@f:@g`: from every copy of @f, the functions named by symbol, followed
// from body to body, include @g or a copy of it.
LogicalResult reaches(const Request<Pair> &request) {
  StringRef target = request.argument.callee.name;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface start : request.argument.caller.functions) {
    // Every function reached from the body of `start`, each once; a
    // function without a body in the module calls nothing back.
    auto edges = [&](Operation *fn) {
      auto function = cast<FunctionOpInterface>(fn);
      return function.isExternal() ? SmallVector<Operation *>() : callees(symbols, fn);
    };
    if (llvm::any_of(reachable(callees(symbols, start), edges), [&](Operation *fn) {
          return names(cast<FunctionOpInterface>(fn), target);
        }))
      continue;
    fail(start->getLoc(), request.property)
        << where(start) << " reaches no function made from @" << target;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
