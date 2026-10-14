// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The guards, idr.check.*. Each gives its operand as its result once its
// condition held, and a guard of an index is the check of the array access
// that takes that result as its index, directly or through the access's own
// guard: an index checked against a size kept beside the array is checked
// again against the array's length.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/InBounds.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::inbounds {

// Each guard of a chain is defined before the next, so the walk ends. A
// string's index has no array access, and none is returned.
std::optional<Value> accessedArray(CheckInBoundsOp guard) {
  Value checked = guard.getChecked();
  for (Operation *user : checked.getUsers()) {
    if (auto get = dyn_cast<ArrayGetOp>(user); get && llvm::is_contained(get.getIndices(), checked))
      return get.getArray();
    if (auto set = dyn_cast<ArraySetOp>(user); set && llvm::is_contained(set.getIndices(), checked))
      return set.getArray();
    // Checked against a size before the access's own guard checks it
    // against the array's length: the access is that guard's.
    if (auto next = dyn_cast<CheckInBoundsOp>(user); next && next.getIndex() == checked)
      if (std::optional<Value> array = accessedArray(next))
        return array;
  }
  return std::nullopt;
}

// The one it measures while it is still a dimension, else the one its
// access reads, once canonicalization has folded the dimension of an array
// made here into the size it was made with. The guard's length is that
// array's only where the length relation proves it so, so what an array the
// length is not would say is still true.
std::optional<Value> guardedArray(CheckInBoundsOp guard) {
  if (std::optional<Value> array = measured(guard.getLength()))
    return array;
  return accessedArray(guard);
}

} // namespace idr::inbounds
