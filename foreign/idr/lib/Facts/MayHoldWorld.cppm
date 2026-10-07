// idr.facts:mayholdworld: whether a value of a type may hold a world.
export module idr.facts:mayholdworld;

import idr.mlir;
import idr.dialect;

import :contained;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Whether a value of `type` may hold a world: a world, or data with a field
// that may. A closure never captures one, so a world reaches a function only
// through its parameters.
bool mayHoldWorld(Operation *from, Type type) {
  return contained(from, type, [](Type type, DataOp) { return isWorld(type); });
}

} // namespace idr::facts
