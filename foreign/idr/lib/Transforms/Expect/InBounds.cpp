// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// in-bounds, bounds-checked and no-guards: which guards a function keeps.
// A proof is the guard's absence: idr-in-bounds and the guards' folders
// erase a guard whose condition holds where it runs, and lowering checks
// those left.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/InBounds.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The ops in `functions` that `keep` selects.
SmallVector<Operation *> opsIn(ArrayRef<FunctionOpInterface> functions,
                               function_ref<bool(Operation *)> keep) {
  SmallVector<Operation *> found;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (keep(op))
        found.push_back(op);
    });
  return found;
}

bool isIndexGuard(Operation *op) { return isa<CheckInBoundsOp>(op); }

// A guard of an index that an array access takes: the access's own check,
// or a check against a size whose result that check takes.
bool isAccessGuard(Operation *op) {
  auto guard = dyn_cast<CheckInBoundsOp>(op);
  return guard && inbounds::accessedArray(guard);
}

bool isGuard(Operation *op) { return isa<GuardOpInterface>(op); }

// Each of `guards` left where it should be gone, one error each.
LogicalResult noneLeft(ArrayRef<Operation *> guards, StringRef property) {
  for (Operation *guard : guards)
    fail(guard->getLoc(), property) << guard->getName() << " is left in " << where(guard);
  return success(guards.empty());
}

} // namespace

// The function the argument names keeps no guard of an index: every array
// access in it was proven within its array, and it has one.
LogicalResult inBounds(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "in-bounds";
  SmallVector<FunctionOpInterface> functions =
      named(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (functions.empty())
    return failure();
  if (opsIn(functions, [](Operation *op) { return isa<ArrayGetOp, ArraySetOp>(op); }).empty()) {
    fail(functions.front()->getLoc(), property) << "no array access in " << function;
    return failure();
  }
  return noneLeft(opsIn(functions, isIndexGuard), property);
}

// Some array access in the function the argument names keeps a check of
// its index: its own, or one against a size whose result its own takes.
LogicalResult boundsChecked(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "bounds-checked";
  SmallVector<FunctionOpInterface> functions =
      named(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (functions.empty())
    return failure();
  if (!opsIn(functions, isAccessGuard).empty())
    return success();
  fail(functions.front()->getLoc(), property) << "no array access is checked in " << function;
  return failure();
}

// The function the argument names keeps no guard of any kind: every
// condition its partial primitives need is proven where it runs.
LogicalResult noGuards(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "no-guards";
  SmallVector<FunctionOpInterface> functions =
      named(module, analyses.getAnalysis<SymbolTable>(), function, property);
  if (functions.empty())
    return failure();
  return noneLeft(opsIn(functions, isGuard), property);
}

} // namespace idr::expect
