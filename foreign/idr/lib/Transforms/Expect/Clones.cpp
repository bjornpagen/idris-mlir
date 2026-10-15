// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// one-clone: every call of a function, or of a copy of it, calls one and
// the same function: the calls share one specialization (or none was
// made), however many copies the passes made on the way.

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

} // namespace idr::expect
