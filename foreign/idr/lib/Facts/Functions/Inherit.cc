// The facts of a clone, from those of its origin and its closures' labels.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

void facts::inherit(func::FuncOp made, func::FuncOp origin, ArrayRef<func::FuncOp> labels) {
  Effects effects = of(origin);
  for (func::FuncOp label : labels)
    effects |= of(label);
  effects.io |= takesWorld(made);
  record(made, effects);
}
