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
LogicalResult reaches(ModuleOp module, AnalysisManager &analyses, StringRef argument) {
  constexpr StringRef property = "reaches";
  auto [from, to] = splitAt(module, argument, property);
  if (from.empty())
    return failure();
  StringRef target = to.ltrim('@');
  if (target.empty())
    return fail(module.getLoc(), property) << "name both functions, as reaches=@f:@g";
  SmallVector<FunctionOpInterface> starts = named(module, from, property);
  if (starts.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface start : starts) {
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
    fail(start->getLoc(), property) << where(start) << " reaches no function made from " << to;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
