// reuses-in-place: what reference counting left in a function, stated as
// the property a test wants of it: it builds in reused cells.
export module idr.expect:reusesInPlace;

import idr.mlir;
import idr.dialect;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

// In the function the argument names, every box is built in the cell of
// one that died (idr.reuse), and at least one is: no box gets a fresh cell.
//
// The function and its clones together: at least one of them builds in a
// reused cell, and none gets a fresh one.
export LogicalResult reusesInPlace(ModuleOp module, StringRef function) {
  constexpr StringRef property = "reuses-in-place";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true, reused = false;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (isa<ReuseOp>(op))
        reused = true;
      auto con = dyn_cast<ConOp>(op);
      if (con && isa<BoxType>(unrestricted(con.getType()))) {
        fail(op->getLoc(), property) << "a box of " << con.getCtor() << " gets a fresh cell in "
                                     << where(op);
        held = false;
      }
    });
  if (!reused) {
    fail(functions.front().getLoc(), property) << "nothing is built in a reused cell in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
