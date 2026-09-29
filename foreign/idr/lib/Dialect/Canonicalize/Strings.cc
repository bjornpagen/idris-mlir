// Output and the first character of a string being built: the DRR patterns
// of Canonicalize.td, and the empty string, which DRR cannot match.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

#include "idr/IdrCanonicalize.inc"

// Writing the empty string writes nothing.
struct PutStrOfEmpty : OpRewritePattern<PutStrOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(PutStrOp op, PatternRewriter &rewriter) const final {
    StringAttr text;
    if (!matchPattern(op.getStr(), m_Constant(&text)) || !text.getValue().empty())
      return failure();
    rewriter.replaceOp(op, op.getWorld());
    return success();
  }
};

} // namespace

void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble, PutStrOfEmpty>(context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble>(context);
}
