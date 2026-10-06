// in-bounds and bounds-checked: which of a function's array accesses
// idr-in-bounds proved within their arrays, as their crash causes say.
export module idr.expect:inBounds;

import idr.mlir;
import idr.dialect;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

namespace {

// The array accesses in `functions`, each with whether it is proven.
SmallVector<std::pair<Operation *, bool>> accesses(ArrayRef<func::FuncOp> functions) {
  SmallVector<std::pair<Operation *, bool>> found;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (auto get = dyn_cast<ArrayGetOp>(op))
        found.push_back({op, !get.getCrashCause()});
      else if (auto set = dyn_cast<ArraySetOp>(op))
        found.push_back({op, !set.getCrashCause()});
    });
  return found;
}

} // namespace

// Every array access in the function the argument names is proven in
// bounds, and it has one.
export LogicalResult inBounds(ModuleOp module, StringRef function) {
  constexpr StringRef property = "in-bounds";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  SmallVector<std::pair<Operation *, bool>> found = accesses(functions);
  if (found.empty()) {
    fail(functions.front().getLoc(), property) << "no array access in " << function;
    return failure();
  }
  bool held = true;
  for (auto [op, proven] : found)
    if (!proven) {
      fail(op->getLoc(), property) << op->getName() << " is checked in " << where(op);
      held = false;
    }
  return success(held);
}

// Some array access in the function the argument names keeps its check.
export LogicalResult boundsChecked(ModuleOp module, StringRef function) {
  constexpr StringRef property = "bounds-checked";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  if (llvm::any_of(accesses(functions), [](auto access) { return !access.second; }))
    return success();
  fail(functions.front().getLoc(), property) << "no array access is checked in " << function;
  return failure();
}

} // namespace idr::expect
