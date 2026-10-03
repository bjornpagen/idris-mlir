// Whether a type is a linear value other than the world.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::isLinear(Type type) {
  return gradeOf(type).quantity == Quantity::One && !isWorld(type);
}
