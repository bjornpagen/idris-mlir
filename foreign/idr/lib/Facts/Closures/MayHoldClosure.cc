// Whether a value of a type may hold a closure.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

namespace {

bool holdsClosure(Operation *from, Type type, llvm::SmallDenseSet<Type> &seen) {
  type = unrestricted(type);
  if (isa<FnType>(type))
    return true;
  DataOp data = lookupData(from, type);
  if (data && data.getClosures())
    return true;
  if (!data || !seen.insert(type).second)
    return false;
  return llvm::any_of(data.getCtors(), [&](CtorOp ctor) {
    return llvm::any_of(ctor.getFieldTypes().getAsValueRange<TypeAttr>(),
                        [&](Type field) { return holdsClosure(from, field, seen); });
  });
}

} // namespace

bool facts::mayHoldClosure(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsClosure(from, type, seen);
}
