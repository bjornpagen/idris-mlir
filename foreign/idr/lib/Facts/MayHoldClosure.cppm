// idr.facts:mayholdclosure: whether a value of a type may hold a closure.
export module idr.facts:mayholdclosure;

import idr.mlir;
import idr.dialect;

import :contained;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Whether a value of `type` may hold a closure: a closure, a sum of
// closures that idr-defunctionalize made, or data with a field that may.
bool mayHoldClosure(Operation *from, Type type) {
  return contained(from, type, [](Type type, DataOp data) {
    return isa<FnType>(type) || (data && data.getClosures());
  });
}

} // namespace idr::facts
