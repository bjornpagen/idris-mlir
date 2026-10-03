// The grade of a type: its own for !idr.q, (w, .) for a plain type.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Grade idr::gradeOf(Type type) {
  auto q = dyn_cast<QType>(type);
  return q ? q.getGrade() : Grade{};
}
