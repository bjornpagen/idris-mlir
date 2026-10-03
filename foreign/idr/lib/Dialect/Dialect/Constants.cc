// The dialect's constants, as folding materializes them.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// idr.constant for the dialect's values and strings, and
// arith.constant for scalars.
Operation *IdrDialect::materializeConstant(OpBuilder &builder, Attribute value,
                                           Type type, Location loc) {
  if (ConstantOp::isBuildableWith(value, type))
    return ConstantOp::create(builder, loc, type, value);
  if (arith::ConstantOp::isBuildableWith(value, type))
    return arith::ConstantOp::create(builder, loc, type, cast<TypedAttr>(value));
  return nullptr;
}
