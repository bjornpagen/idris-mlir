// Whether a function takes a world.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

bool facts::takesWorld(func::FuncOp fn) {
  return llvm::any_of(fn.getArgumentTypes(),
                      [&](Type type) { return mayHoldWorld(fn, type); });
}
