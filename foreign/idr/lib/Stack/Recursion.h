// Which functions may have more than one frame live at a time, and which
// share a cycle of calls.
#pragma once

#include "idr/Idr.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

namespace idr::stack {

// The cycles of calls among the functions of `module`: a call names its
// callee, and an idr.apply may call any function whose address is taken (a
// closure, a closure constant, or any other use of its symbol but a call's
// callee).
class Cycles {
public:
  explicit Cycles(mlir::ModuleOp module);

  // Whether `fn` is on a cycle of calls, so that it may have more than one
  // frame live at a time. A function's call of itself in tail position does
  // not count: idr-tail-loops makes it the next iteration of a loop in the
  // same frame. A function on no cycle has at most one frame on the stack
  // at a time.
  bool recursive(mlir::Operation *fn) const { return onCycle.contains(fn); }

  // Whether `a` and `b` are on one cycle of calls: each may call the other,
  // through any calls. A function is on one with itself.
  bool together(mlir::Operation *a, mlir::Operation *b) const;

private:
  llvm::DenseMap<mlir::Operation *, unsigned> component;
  llvm::DenseSet<mlir::Operation *> onCycle;
};

} // namespace idr::stack
