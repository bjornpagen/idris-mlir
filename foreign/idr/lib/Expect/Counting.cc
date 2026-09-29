// reuses-in-place and counts-nothing: what reference counting left in one
// function, stated as the property a test wants of it rather than as the
// ops that show it.

#include "Expect/Expect.h"

using namespace mlir;

namespace idr::expect {

LogicalResult reusesInPlace(ModuleOp module, StringRef function) {
  constexpr StringRef property = "reuses-in-place";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true, reused = false;
  fn.walk([&](Operation *op) {
    if (isa<ReuseOp>(op))
      reused = true;
    auto con = dyn_cast<ConOp>(op);
    if (con && isa<BoxType>(con.getType())) {
      fail(op->getLoc(), property) << "a box of " << con.getCtor() << " gets a fresh cell in "
                                   << where(op);
      held = false;
    }
  });
  if (!reused) {
    fail(fn.getLoc(), property) << "nothing is built in a reused cell in " << where(fn);
    held = false;
  }
  return success(held);
}

LogicalResult countsNothing(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counts-nothing";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  bool held = true;
  fn.walk([&](Operation *op) {
    if (!isa<IncOp, DecOp>(op))
      return;
    fail(op->getLoc(), property) << op->getName() << " in " << where(op);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
