// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// tests-nothing: a function tests no count and no null.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names tests no count and no null: every take
// in it is of an exclusive value, every reuse builds in an exclusive
// cell, and there is at least one take.
LogicalResult testsNothing(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "tests-nothing";
  SmallVector<FunctionOpInterface> functions =
      named(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (functions.empty())
    return failure();
  bool held = true, taken = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      Value cell;
      if (auto take = dyn_cast<TakeOp>(op)) {
        taken = true;
        cell = take.getValue();
      } else if (auto reuse = dyn_cast<ReuseOp>(op)) {
        cell = reuse.getToken();
      }
      if (!cell || isExclusive(cell.getType()))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op) << " tests a value of "
                                   << cell.getType() << ", which is not exclusive";
      held = false;
    });
  if (!taken) {
    fail(functions.front()->getLoc(), property) << "nothing is taken apart in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
