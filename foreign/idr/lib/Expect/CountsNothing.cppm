// counts-nothing: a function counts no reference.
export module idr.expect:countsNothing;

import idr.mlir;
import idr.dialect;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

// The function the argument names counts no reference: no idr.dup, no
// idr.drop.
export LogicalResult countsNothing(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counts-nothing";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (!isa<DupOp, DropOp>(op))
        return;
      // Static data holds no count: a reference to it costs nothing.
      if (auto dup = dyn_cast<DupOp>(op); dup && matchPattern(dup.getValue(), m_Constant()))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
