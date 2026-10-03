// A value held at another quantity of its own type.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Value idr::heldAs(OpBuilder &b, Location loc, Value value, Type type) {
  if (value.getType() == type)
    return value;
  if (quantityOf(type) == Quantity::One)
    return LinEnterOp::create(b, loc, type, value);
  return LinUseOp::create(b, loc, type, value);
}
