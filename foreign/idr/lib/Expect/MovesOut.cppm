// moves-out: a read of an array's element whose next IO writes that
// element moves it out, stated as the property a test wants of it: some
// read gives the reference the array held, so the value it rebuilds holds
// the one reference to its cell.
export module idr.expect:movesOut;

import idr.mlir;
import idr.dialect;

import :report;
import :roots;

using namespace mlir;

namespace idr::expect {

// In the function the argument names and its clones, or anywhere, some
// idr.array.get moves its element out.
export LogicalResult movesOut(ModuleOp module, StringRef function) {
  constexpr StringRef property = "moves-out";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool moved = false;
  for (Operation *root : roots)
    root->walk([&](ArrayGetOp get) { moved = moved || get.getMoves(); });
  if (!moved)
    fail(roots.front()->getLoc(), property)
        << "no read of an element moves it out of its array"
        << (function.empty() ? "" : " in ") << function;
  return success(moved);
}

} // namespace idr::expect
