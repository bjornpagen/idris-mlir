// Whether a value holds a reference of its own: the owned stage's own or
// excl.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::isOwned(Type type) {
  Permission permission = gradeOf(type).permission;
  return permission == Permission::Own || permission == Permission::Excl;
}
