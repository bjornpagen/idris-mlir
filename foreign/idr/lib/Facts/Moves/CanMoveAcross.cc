// Whether an op only computes.
module idr.facts;

import idr.mlir;

using namespace mlir;

bool idr::facts::canMoveAcross(Operation *op) {
  return only(op, [](const Effects &effects) { return effects.none(); });
}
