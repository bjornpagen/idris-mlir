// A finite Double constant: no cast of it crashes.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownFinite(Value value) {
  FloatAttr constant;
  return matchPattern(value, m_Constant(&constant)) && constant.getValue().isFinite();
}
