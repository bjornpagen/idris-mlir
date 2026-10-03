// Whether a value of a type may hold a world.
module idr.facts;

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

bool facts::mayHoldWorld(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsWorld(from, type, seen);
}
