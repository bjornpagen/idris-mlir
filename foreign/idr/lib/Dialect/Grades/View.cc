// The view of a type: its quantity, owning nothing.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::view(Type type) {
  return graded({gradeOf(type).quantity, Permission::None}, unrestricted(type));
}
