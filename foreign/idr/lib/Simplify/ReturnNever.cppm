// idr.simplify:returnNever: the end of a function body that never returns.
export module idr.simplify:returnNever;

import idr.mlir;

using namespace mlir;

namespace idr::simplify {

// The end of the body of `fn` where it never returns: poison of each of
// its result types, returned, which is never reached. No function body
// ends in ub.unreachable, which the pinned inliner cannot inline, and the
// program's verifier refuses one that does.
export func::ReturnOp returnNever(OpBuilder &b, Location loc, func::FuncOp fn) {
  SmallVector<Value> results = llvm::map_to_vector(fn.getResultTypes(), [&](Type type) -> Value {
    return ub::PoisonOp::create(b, loc, type);
  });
  return func::ReturnOp::create(b, loc, results);
}

} // namespace idr::simplify
