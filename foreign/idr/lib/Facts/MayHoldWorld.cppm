// idr.facts:mayholdworld: whether a value of a type may hold a world.
export module idr.facts:mayholdworld;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

bool holdsWorld(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  if (isWorld(type))
    return true;
  type = unrestricted(type);
  DataOp data = lookupData(from, type);
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return holdsWorld(from, field, seen); });
  });
}

} // namespace

export namespace idr::facts {

// Whether a value of `type` may hold a world: a world, or data with a field
// that may; a linear value holds what its value does. A closure never
// captures one, so a world reaches a function only through its parameters.
bool mayHoldWorld(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsWorld(from, type, seen);
}

} // namespace idr::facts
