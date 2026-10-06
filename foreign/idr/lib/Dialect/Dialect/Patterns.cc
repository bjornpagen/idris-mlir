// The dialect's canonicalization patterns, which canonicalize adds to
// every op's.

#include "idr/Idr.h"

#include "mlir/Dialect/MemRef/Transforms/Transforms.h"

using namespace mlir;
using namespace idr;

// The dimension of an array, `memref.dim` of an `idr.array.new`, is the
// size the array was made with: upstream's resolution of a dimension
// through ReifyRankedShapedTypeOpInterface, which idr.array.new
// implements, as a canonicalization.
void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  memref::populateResolveRankedShapedTypeResultDimsPatterns(results);
}
