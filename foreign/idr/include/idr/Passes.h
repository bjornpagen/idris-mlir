// What the optimization passes (lib/Passes/) offer the rest of the compiler.
#pragma once

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/Builders.h"

#include "llvm/ADT/SmallVector.h"

#include <string>

namespace idr {

// The passes of one round of idr-simplify, as textual pipelines,
// in order.
llvm::SmallVector<std::string> simplifyRound(unsigned inlineIterations);

// The end of the body of `fn` where it never returns: poison of each of
// its result types, returned, which is never reached. No function body
// ends in ub.unreachable, which the pinned inliner cannot inline, and the
// program's verifier refuses one that does.
mlir::func::ReturnOp returnNever(mlir::OpBuilder &b, mlir::Location loc, mlir::func::FuncOp fn);

} // namespace idr
