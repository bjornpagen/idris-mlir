// A constant other than zero, an integer or a big: a guard of a divisor
// folds away on it.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

bool idr::knownNonZero(Value value) {
  Attribute constant;
  return matchPattern(value, m_Constant(&constant)) && checkHolds(CheckKind::Nonzero, constant);
}
