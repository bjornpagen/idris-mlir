// idr.facts:takesworld: whether a function takes a world.
export module idr.facts:takesworld;

import idr.mlir;

import :mayholdworld;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// Whether `fn` takes a world, in a parameter or in data one holds.
bool takesWorld(func::FuncOp fn) {
  return llvm::any_of(fn.getArgumentTypes(),
                      [&](Type type) { return mayHoldWorld(fn, type); });
}

} // namespace idr::facts
