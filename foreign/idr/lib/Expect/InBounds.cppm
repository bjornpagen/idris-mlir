// in-bounds, bounds-checked and no-guards: which guards a function keeps.
// A proof is the guard's absence: idr-in-bounds and the guards' folders
// erase a guard whose condition holds where it runs, and lowering checks
// those left.
export module idr.expect:inBounds;

import idr.mlir;
import idr.dialect;
import idr.inbounds;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

namespace {

// The ops in `functions` that `keep` selects.
SmallVector<Operation *> opsIn(ArrayRef<func::FuncOp> functions,
                               function_ref<bool(Operation *)> keep) {
  SmallVector<Operation *> found;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (keep(op))
        found.push_back(op);
    });
  return found;
}

bool isIndexGuard(Operation *op) { return isa<CheckInBoundsOp>(op); }

// A guard of an index that an array access takes, the access's own check.
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
export LogicalResult inBounds(ModuleOp module, StringRef function) {
  constexpr StringRef property = "in-bounds";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  if (opsIn(functions, [](Operation *op) { return isa<ArrayGetOp, ArraySetOp>(op); }).empty()) {
    fail(functions.front().getLoc(), property) << "no array access in " << function;
    return failure();
  }
  return noneLeft(opsIn(functions, isIndexGuard), property);
}

// Some array access in the function the argument names keeps its check.
export LogicalResult boundsChecked(ModuleOp module, StringRef function) {
  constexpr StringRef property = "bounds-checked";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  if (!opsIn(functions, isAccessGuard).empty())
    return success();
  fail(functions.front().getLoc(), property) << "no array access is checked in " << function;
  return failure();
}

// The function the argument names keeps no guard of any kind: every
// condition its partial primitives need is proven where it runs.
export LogicalResult noGuards(ModuleOp module, StringRef function) {
  constexpr StringRef property = "no-guards";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  return noneLeft(opsIn(functions, isGuard), property);
}

} // namespace idr::expect
