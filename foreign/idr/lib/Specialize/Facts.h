// The facts a clone inherits, and what raising asks of a callee.
#pragma once

#include "idr/Idr.h"

namespace idr::specialize {

// Gives `clone`, which runs the body of `origin` with closures of `labels`
// in it, the facts of `origin` and of the labels together: total if all are
// (a null label, a function not known, is not), pure if all are, able to
// crash if one is. A clone that writes output is not pure.
void inheritFacts(mlir::func::FuncOp clone, mlir::func::FuncOp origin,
                  llvm::ArrayRef<mlir::func::FuncOp> labels, bool writes = false);

// Whether a call of `callee` with `operands` runs to its end at compile
// time: idr-eval evaluates a closed call of a pure, total callee.
bool evaluatesToTheEnd(mlir::func::FuncOp callee, mlir::ValueRange operands);

} // namespace idr::specialize
