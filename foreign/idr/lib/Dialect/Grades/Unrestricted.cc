// The type of the value itself, its grade stripped.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::unrestricted(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getValue() : type;
}
