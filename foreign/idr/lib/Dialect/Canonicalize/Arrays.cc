// A write of an array's element: the read before it, of the same element,
// moves the element out (idr.canon).

#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"

import idr.canon;

using namespace mlir;
using namespace idr;

void ArraySetOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addMoveOutPatterns(results, context);
}
