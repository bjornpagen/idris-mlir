// A constant other than zero, an integer or a big: no division by it
// crashes.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownNonZero(Value value) {
  Attribute constant;
  if (!matchPattern(value, m_Constant(&constant)))
    return false;
  if (auto integer = dyn_cast<IntegerAttr>(constant))
    return !integer.getValue().isZero();
  if (auto big = dyn_cast<BigAttr>(constant))
    return big.getValue() != "0";
  return false;
}
