// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// one-clone and specialized-once: every call of a function, or of a copy
// of it, calls one and the same function: the calls share one
// specialization (or none was made), however many copies the passes made
// on the way; and no copy of a function was made for a call in another
// copy: a specialization's calls of the function go to itself or to the
// function, so the specializations stop after one step, however long the
// recursion.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::expect {

LogicalResult oneClone(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "one-clone";
  StringRef origin = function.ltrim('@');
  if (origin.empty())
    return fail(module.getLoc(), property) << "name the function, as one-clone=@f";
  SymbolTable &symbols = symbolsOf(module, analyses);
  llvm::SetVector<StringRef> targets;
  module.walk([&](CallOp call) {
    auto callee = symbols.lookup<FunctionOpInterface>(call.getCalleeAttr().getAttr());
    if (call.getCallee() == origin || (callee && names(callee, origin)))
      targets.insert(call.getCallee());
  });
  if (targets.empty())
    return fail(module.getLoc(), property) << "no call of " << function << " or of a copy of it";
  if (targets.size() == 1)
    return success();
  InFlightDiagnostic error = fail(module.getLoc(), property) << "the calls of " << function << " reach";
  for (StringRef target : targets)
    error << " @" << target;
  return failure();
}

// Every copy of @f, @f aside, calls of @f and its copies only itself and
// @f.
LogicalResult specializedOnce(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "specialized-once";
  StringRef origin = function.ltrim('@');
  if (origin.empty())
    return fail(module.getLoc(), property) << "name the function, as specialized-once=@f";
  SmallVector<FunctionOpInterface> copies = named(module, function, property);
  if (copies.empty())
    return failure();
  SymbolTable &symbols = symbolsOf(module, analyses);
  bool held = true;
  for (FunctionOpInterface copy : copies) {
    StringRef self = SymbolTable::getSymbolName(copy).getValue();
    if (self == origin)
      continue;
    copy->walk([&](CallOp call) {
      StringRef target = call.getCallee();
      auto callee = symbols.lookup<FunctionOpInterface>(call.getCalleeAttr().getAttr());
      if (target == self || target == origin || !callee || !names(callee, origin))
        return;
      fail(call->getLoc(), property) << where(copy) << ", a copy of " << function << ", calls @"
                                     << target << ", another copy of it";
      held = false;
    });
  }
  return success(held);
}

} // namespace idr::expect
