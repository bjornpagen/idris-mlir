// A type at a grade, in canonical form.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::graded(Grade grade, Type value) {
  if (auto q = dyn_cast<QType>(value))
    value = q.getValue();
  return grade.plain() ? value : QType::get(value.getContext(), grade, value);
}
