// idr.facts:inherit: the facts of a clone, from those of its origin and its
// closures' labels.
export module idr.facts:inherit;

import idr.mlir;

import :effects;
import :of;
import :record;
import :takesworld;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Gives `made`, a new function that runs the body of `origin` with closures
// of `labels` in it (a clone), the effects idr-effects would find: those of
// `origin` and of `labels` together (a null label, one not known, may do
// anything), and IO if it takes a world. Its `idr.total` is its origin's,
// which it was cloned with: its body loops where its origin's does.
void inherit(func::FuncOp made, func::FuncOp origin, ArrayRef<func::FuncOp> labels) {
  Effects effects = of(origin);
  for (func::FuncOp label : labels)
    effects |= of(label);
  effects.io |= takesWorld(made);
  record(made, effects);
}

} // namespace idr::facts
