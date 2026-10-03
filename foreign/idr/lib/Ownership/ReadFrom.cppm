// idr.ownership:readfrom: the value a field was read from.
export module idr.ownership:readfrom;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// The value a field was read from: the operand of an idr.field, or the
// scrutinee of the match whose region binds it; null for any other value.
export Value readFrom(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return field.getValue();
  auto arg = dyn_cast<BlockArgument>(value);
  if (!arg)
    return nullptr;
  if (auto match = dyn_cast_or_null<MatchOp>(arg.getOwner()->getParentOp()))
    return match.getScrutinee();
  return nullptr;
}

} // namespace idr::ownership
