// Idris's product of quantities.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Quantity idr::times(Quantity a, Quantity b) {
  if (a == Quantity::Zero || b == Quantity::Zero)
    return Quantity::Zero;
  if (a == Quantity::One)
    return b;
  if (b == Quantity::One)
    return a;
  return Quantity::Many;
}
