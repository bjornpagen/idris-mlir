// Phase 1 of idr-lower for the loops over an array's index space, after the
// matches: idr.array.generate and idr.array.fold become linalg.generic over
// the arrays, still on idr types.

#ifndef IDR_CONVERSION_ARRAYLOOPS_H
#define IDR_CONVERSION_ARRAYLOOPS_H

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/PatternMatch.h"

namespace idr::conversion {

// The array as a memref a linalg op reads or writes: itself, or a view of
// an owned one.
mlir::Value asMemref(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array);

// The array a view was read from, through the borrows (idr-rc reads an
// owned array where the fold is, inside the body, so the fold's operand
// is a view of a value from outside).
mlir::Value viewed(mlir::Value array);

// if (every array the body of `generic` reads at its index has the elements
// the loop reads) { the generic reading them as inputs } else { the generic }.
void readAsInputs(mlir::RewriterBase &rewriter, mlir::linalg::GenericOp generic);

// The patterns of idr.array.generate and idr.array.fold, for the greedy
// driver going top-down: a generate sees the fold its body is before
// anything lowers it, and a loop cloned into a generic's body is visited in
// its turn.
void populateArrayLoopPatterns(mlir::RewritePatternSet &patterns);

} // namespace idr::conversion

#endif // IDR_CONVERSION_ARRAYLOOPS_H
