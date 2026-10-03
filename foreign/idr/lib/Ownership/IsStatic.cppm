// idr.ownership:isstatic: static values, which no count reaches.
export module idr.ownership:isstatic;

import idr.mlir;
import idr.dialect;

import :readfrom;

using namespace mlir;

namespace idr::ownership {

// Whether `value` is static: a constant, poison, or a field read from one.
export bool isStatic(Value value) {
  for (; value; value = readFrom(value)) {
    Operation *def = value.getDefiningOp();
    if (def && (def->hasTrait<OpTrait::ConstantLike>() || isa<ub::PoisonOp, BigSmallOp, PendingOp>(def)))
      return true;
  }
  return false;
}

} // namespace idr::ownership
