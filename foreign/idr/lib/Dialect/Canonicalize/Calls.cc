// The dialect's patterns on func.call.

#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"

import idr.facts;

using namespace mlir;
using namespace idr;

namespace {

// A call whose results are unused goes when it only computes: its callee
// performs no IO, cannot crash and returns, and so do the closures it is
// given. A crash stays even when its result is unused.
struct RemoveUnusedCall : OpRewritePattern<func::CallOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(func::CallOp call, PatternRewriter &rewriter) const final {
    if (!facts::canDrop(call))
      return failure();
    rewriter.eraseOp(call);
    return success();
  }
};

} // namespace

void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  results.add<RemoveUnusedCall>(getContext());
}
