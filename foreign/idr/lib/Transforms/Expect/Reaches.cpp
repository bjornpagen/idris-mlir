// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reaches: a function's code reaches another's through the functions its
// body names, whatever names them: a call, a dispatch's call of a label, a
// constant. That a run of one may run the other is a fact of the call
// graph, which is complete once every force is a call; which function
// stands between them is the passes' business.

#include "idr/Transforms/Expect.h"

#include "idr/Support/Worklist.h"

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
    // Every function reached from the body of `start`, each once.
    OnceWorklist<Operation *> reached;
    for (Operation *callee : callees(symbols, start))
      reached.push(callee);
    while (std::optional<Operation *> next = reached.pop()) {
      auto fn = cast<FunctionOpInterface>(*next);
      if (!fn.isExternal())
        for (Operation *callee : callees(symbols, fn))
          reached.push(callee);
    }
    if (llvm::any_of(reached.entered(), [&](Operation *fn) {
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
