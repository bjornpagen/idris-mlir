// Tail position: where what an op computes is what its function returns.
#pragma once

#include "idr/Idr.h"

namespace idr::passes {

// Whether the results of `op` pass unchanged to its function's return: the
// op right after it is the terminator and passes exactly them, and is the
// function's return or the yield of a match in tail position itself. A self
// call there becomes the next iteration of a loop in the same frame
// (idr-tail-loops), and a call of another function on the caller's cycle
// of calls a tail call (idr-tail-calls).
bool inTailPosition(mlir::Operation *op);

// Whether `call` is a self call in tail position modulo a constructor: its
// result is a field of the boxed constructor a tail position returns, and
// idr-trmc makes it a tail call that writes the field (Trmc.cc).
bool inTailPositionModuloConstructor(mlir::func::CallOp call);

} // namespace idr::passes
