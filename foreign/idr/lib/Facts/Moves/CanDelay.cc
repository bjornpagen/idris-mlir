// Whether an op may run later.
module idr.facts;

import idr.mlir;

using namespace mlir;

bool idr::facts::canDelay(Operation *op) {
  return only(op, [](const Effects &effects) { return !effects.io; });
}
