// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// one-clone and specialized-once: every call of a function, or of a copy
// of it, calls one and the same function: the calls share one
// specialization (or none was made), however many copies the passes made
// on the way; and no copy of a function was made for a call in another
// copy: a specialization's calls of the function go to itself or to the
// function, so the specializations stop after one step, however long the
// recursion.

#include "Checks.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::expect {

// Every call of @f, or of a copy of it, calls one function.
LogicalResult oneClone(const Request<Symbol> &request) {
  const Symbol &origin = request.argument;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  llvm::SetVector<StringRef> targets;
  request.module->walk([&](CallOpInterface call) {
    if (callsNamed(call, origin, symbols))
      targets.insert(calleeOf(call).getRootReference().getValue());
  });
  if (targets.empty())
    return fail(request.module->getLoc(), request.property)
           << "no call of @" << origin.name << " or of a copy of it";
  if (targets.size() == 1)
    return success();
  InFlightDiagnostic error = fail(request.module->getLoc(), request.property)
                             << "the calls of @" << origin.name << " reach";
  for (StringRef target : targets)
    error << " @" << target;
  return failure();
}

// Every copy of @f, @f aside, calls of @f and its copies only itself and
// @f.
LogicalResult specializedOnce(const Request<Functions> &request) {
  StringRef origin = request.argument.name;
  SymbolTable &symbols = symbolsOf(request.module, request.analyses);
  bool held = true;
  for (FunctionOpInterface copy : request.argument.functions) {
    StringRef self = SymbolTable::getSymbolName(copy).getValue();
    if (self == origin)
      continue;
    copy->walk([&](CallOpInterface call) {
      SymbolRefAttr named = calleeOf(call);
      if (!named)
        return;
      StringRef target = named.getRootReference().getValue();
      auto callee = symbols.lookup<FunctionOpInterface>(named.getRootReference());
      if (target == self || target == origin || !callee || !names(callee, origin))
        return;
      fail(call->getLoc(), request.property) << where(copy) << ", a copy of @" << origin
                                             << ", calls @" << target << ", another copy of it";
      held = false;
    });
  }
  return success(held);
}

} // namespace idr::expect
