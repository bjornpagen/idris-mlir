// idr.inbounds:guards: the guards, idr.check.*. Each gives its operand as
// its result once its condition held, and a guard of an index is the check
// of the array access that takes that result as its index.
export module idr.inbounds:guards;

import idr.mlir;
import idr.dialect;

import :joins;

using namespace mlir;

namespace idr::inbounds {

// The array of the access whose index is `guard`'s result. None when no
// array access takes it, as for a string's index.
export std::optional<Value> accessedArray(CheckInBoundsOp guard) {
  Value checked = guard.getChecked();
  for (Operation *user : checked.getUsers()) {
    if (auto get = dyn_cast<ArrayGetOp>(user); get && get.getIndex() == checked)
      return get.getArray();
    if (auto set = dyn_cast<ArraySetOp>(user); set && set.getIndex() == checked)
      return set.getArray();
  }
  return std::nullopt;
}

// The array whose length `guard`'s length stands for: the one it measures,
// while it is still a dimension, else the one its access reads, once
// canonicalization has folded the dimension of an array made here into the
// size it was made with. The guard's length is that array's only where the
// length relation proves it so, so what an array the length is not would
// say is still true.
export std::optional<Value> guardedArray(CheckInBoundsOp guard) {
  if (std::optional<Value> array = measured(guard.getLength()))
    return array;
  return accessedArray(guard);
}

} // namespace idr::inbounds
