// The canonicalization patterns of idr.match and idr.match_lit: upstream's
// region patterns, as scf.index_switch uses them, then idr.canon's. Results
// no region needs drop, and a match whose taken region is known (a constant
// or an idr.con scrutinee, or one region left) is replaced by that region,
// whose arguments become idr.field reads that fold. Upstream's defaults for
// the region of a literal match, which binds nothing, are local to its
// header, so these hooks add the region patterns themselves.

#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/RegionUtils.h"

import idr.canon;

using namespace mlir;
using namespace idr;

void MatchOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName(), canon::readField,
                                                 canon::readsPlainValue);
  canon::addMatchPatterns(results, context);
}

void MatchLitOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                             MLIRContext *context) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, getOperationName());
  canon::addMatchLitPatterns(results, context);
}
