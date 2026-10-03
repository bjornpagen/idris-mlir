// idr.ownership:verify: the owned stage's rule: each reference is consumed exactly once on every
// path, and a view is used only while its owner holds its reference. The
// grades say which is which (`!idr.own<T>` holds one reference, plain T
// holds none) and the position table (useOf) says what each use does; the
// rule extends the world's (Dialect.cc), which counts uses on the worst
// path, to exact counts: a walk of each function follows the references
// every owned value holds along the ops, taking the regions of a match as
// alternatives that must agree where they meet again.
//
// Runs as the verifier of the module's `idr.stage`, before the ops inside
// are verified, so it assumes no op is well formed beyond what it checks.
export module idr.ownership:verify;

import idr.mlir;
import idr.layout;

import :checker;
import :counting;

using namespace mlir;

namespace idr::ownership {

// The verifier of the owned stage: every reference is consumed exactly once
// on every path, no value is used after its last reference is gone, and
// every idr.reuse builds in a cell of its own size.
export LogicalResult verifyOwned(ModuleOp module) {
  Counting counting(module);
  SymbolTableCollection symbols;
  // Only a reuse needs the sizes of cells.
  std::optional<FailureOr<layout::Layouts>> cells;
  auto layouts = [&]() -> layout::Layouts * {
    if (!cells)
      cells.emplace(layout::Layouts::of(module));
    return succeeded(*cells) ? &**cells : nullptr;
  };
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    Checker checker(counting, symbols, layouts);
    if (failed(checker.check(fn)))
      return failure();
  }
  return success();
}

} // namespace idr::ownership
