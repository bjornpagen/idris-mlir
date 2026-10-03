// A type at another quantity, its permission kept.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::atQuantity(Type type, Quantity quantity) {
  return graded({quantity, gradeOf(type).permission}, unrestricted(type));
}
