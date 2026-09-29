// Which functions may have more than one frame live at a time.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseSet.h"

namespace idr::stack {

// The functions of `module` on a cycle of calls: a call names its callee,
// and an idr.apply may call any function whose address is taken (a closure,
// a closure constant, or any other use of its symbol but a call's callee).
// A function's call of itself in tail position does not count: idr-tail-loops
// makes it the next iteration of a loop in the same frame. A function on
// no cycle has at most one frame on the stack at a time.
llvm::DenseSet<mlir::Operation *> recursiveFunctions(mlir::ModuleOp module);

} // namespace idr::stack
