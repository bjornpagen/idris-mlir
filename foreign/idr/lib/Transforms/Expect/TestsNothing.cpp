// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// tests-nothing and exclusive-copy: a function tests no count and no null,
// and a function was given an exclusive copy, which idr-rc makes where
// every reference it is passed is the only one to its cells.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names tests no count and no null: every take
// in it is of an exclusive value, every cell it recycles is an exclusive
// token's, and there is at least one take.
LogicalResult testsNothing(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, taken = false;
  auto tested = [&](Operation *op, Value value) {
    if (isExclusive(value.getType()))
      return;
    fail(op->getLoc(), request.property) << op->getName() << " in " << where(op)
                                         << " tests a value of " << value.getType()
                                         << ", which is not exclusive";
    held = false;
  };
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (auto take = dyn_cast<TakeOp>(op)) {
        taken = true;
        tested(op, take.getValue());
      } else if (auto recycle = dyn_cast<CellRecycleOp>(op)) {
        tested(op, recycle.getToken());
      }
    });
  if (!taken) {
    fail(functions.front()->getLoc(), request.property)
        << "nothing is taken apart in @" << request.argument.name;
    held = false;
  }
  return success(held);
}

// Some copy of @f takes every parameter that holds references at the
// exclusive grade, and takes one.
LogicalResult exclusiveCopy(const Request<Functions> &request) {
  auto exclusiveOnly = [](FunctionOpInterface fn) {
    auto references = llvm::make_filter_range(fn.getArgumentTypes(), holdsReferences);
    return !references.empty() && llvm::all_of(references, isExclusive);
  };
  if (llvm::any_of(request.argument.functions, exclusiveOnly))
    return success();
  return fail(request.module->getLoc(), request.property)
         << "no copy of @" << request.argument.name << " takes its references exclusive";
}

} // namespace idr::expect
