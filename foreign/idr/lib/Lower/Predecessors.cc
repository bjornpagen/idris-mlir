// Phase 1 of idr-lower, after the matches: the predecessor of a big is the
// runtime's subtraction of one.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

void lowerPredecessors(ModuleOp module) {
  module.walk([](BigPredOp pred) {
    OpBuilder b(pred);
    Location loc = pred.getLoc();
    auto big = BigType::get(b.getContext());
    Value one = ConstantOp::create(b, loc, big, BigAttr::get(b.getContext(), "1"));
    pred.replaceAllUsesWith(BigSubOp::create(b, loc, pred.getValue(), one).getResult());
    pred.erase();
  });
}

} // namespace idr::lower
