// A finite Double constant: a guard of a cast folds away on it.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownFinite(Value value) {
  Attribute constant;
  return matchPattern(value, m_Constant(&constant)) && checkHolds(CheckKind::Finite, constant);
}
