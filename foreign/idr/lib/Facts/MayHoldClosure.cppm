// idr.facts:mayholdclosure: whether a value of a type may hold a closure.
export module idr.facts:mayholdclosure;

import idr.mlir;
import idr.dialect;

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

export namespace idr::facts {

// Whether a value of `type` may hold a closure: a closure, a sum of
// closures that idr-defunctionalize made, or data with a field that may; a
// linear value holds what its value does.
bool mayHoldClosure(Operation *from, Type type) {
  llvm::SmallDenseSet<Type> seen;
  return holdsClosure(from, type, seen);
}

} // namespace idr::facts
