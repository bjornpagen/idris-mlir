// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// contified: every continuation became part of the function it continues.
// A function whose one call is from another function, which it calls back,
// is a continuation of that function (a case block of Idris's recursion
// through an `if`), which MLIR's inliner never inlines, and idr-contify
// makes it a join point there; which functions it was is the passes'
// business, that none is left is the property.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::expect {

// The calls are the program graph's, the one index of a first-order
// program's calls, which contify reads too: so the property is one of a
// program past defunctionalization, whose every call names its callee,
// and before the lowering, which leaves no idr.func to count. The root is
// entered from outside the program, so it is no continuation however its
// functions call it.
LogicalResult contified(const Request<Nothing> &request) {
  auto program = dyn_cast<ProgramOp>(programOf(request.module));
  if (!program || closuresAt[program.getStage()] != StageClosures::FirstOrder ||
      functionsAt[program.getStage()] != StageFunctions::Ours)
    return fail(request.module->getLoc(), request.property)
           << "is stated of a first-order program before its lowering, which the module does "
              "not hold";
  const solver::ProgramGraph &graph =
      request.analyses.nest(program).getAnalysis<solver::ProgramGraph>();
  solver::FunctionId root = graph.id(program.getRootAttr());
  bool held = true;
  for (solver::FunctionId fn : graph.functions()) {
    if (fn == root || graph.callSites(fn) != 1)
      continue;
    solver::FunctionId caller = graph.callers(fn).front();
    if (caller == fn || !llvm::is_contained(graph.callers(caller), fn))
      continue;
    fail(graph.op(fn).getLoc(), request.property)
        << where(graph.op(fn)) << " is called once, from " << where(graph.op(caller))
        << ", which it calls back, and is still a function";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
