// idr.ops:isbyte: a constant that is a byte, which idr.to_byte folds and
// never crashes on.
export module idr.ops:isbyte;

import idr.mlir;

using namespace mlir;

export namespace idr::ops {

// A constant that is a byte: 0 to 255.
bool isByte(Attribute constant) {
  auto value = dyn_cast_or_null<IntegerAttr>(constant);
  return value && !value.getValue().isNegative() && value.getValue().isIntN(8);
}

} // namespace idr::ops
