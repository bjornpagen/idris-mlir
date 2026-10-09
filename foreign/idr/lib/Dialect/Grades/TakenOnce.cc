// Whether a value is used as a closure or a suspension holding a linear
// value may be.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// Not at all, or once: run by its one user, or entered into a linear type.
bool idr::takenOnce(Value value) {
  if (value.use_empty())
    return true;
  if (!value.hasOneUse())
    return false;
  Operation *user = *value.getUsers().begin();
  if (auto apply = dyn_cast<ApplyOp>(user))
    return apply.getCallee() == value;
  if (auto force = dyn_cast<ForceOp>(user))
    return force.getSuspension() == value;
  return isa<LinEnterOp>(user);
}
