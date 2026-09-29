// Tail position, as idr-tail-loops sees it.
#pragma once

#include "idr/Idr.h"

namespace idr::stack {

// Whether the results of `op` pass unchanged to its function's return: the
// op right after it is the terminator and passes exactly them, and is the
// function's return or the yield of a match in tail position itself. A
// self call there becomes the next iteration of a loop in the same frame.
bool inTailPosition(mlir::Operation *op);

} // namespace idr::stack
