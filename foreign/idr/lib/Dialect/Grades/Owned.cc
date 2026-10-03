// A type at an owned grade, its quantity kept.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::owned(Type type) {
  Grade grade = gradeOf(type);
  if (grade.permission == Permission::None)
    grade.permission = Permission::Own;
  return graded(grade, unrestricted(type));
}
