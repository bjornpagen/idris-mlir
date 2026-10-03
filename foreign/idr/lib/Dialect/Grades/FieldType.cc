// The type at which a match binds a field of its scrutinee.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::fieldType(Type scrutinee, Type field) {
  if (isWorld(field))
    return field;
  return graded({times(quantityOf(scrutinee), quantityOf(field)), Permission::None},
                unrestricted(field));
}
