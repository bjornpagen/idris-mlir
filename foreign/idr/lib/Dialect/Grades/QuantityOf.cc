// How often a value may be used, as its type says.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// A destination is written exactly once, so it is used exactly once.
idr::Quantity idr::quantityOf(Type type) {
  return isa<DestType>(type) ? Quantity::One : gradeOf(type).quantity;
}
