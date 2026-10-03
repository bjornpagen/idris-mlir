// Whether a value holds the only reference to every cell of its cell
// graph.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::isExclusive(Type type) { return gradeOf(type).permission == Permission::Excl; }
