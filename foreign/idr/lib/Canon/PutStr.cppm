// idr.canon:putstr: output of the empty string, which the DRR patterns of
// idr.io.put_str cannot match.
export module idr.canon:putstr;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

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

export namespace idr::canon {

// Adds the pattern that drops output of the empty string.
void addPutStrOfEmpty(RewritePatternSet &results, MLIRContext *context) {
  results.add<PutStrOfEmpty>(context);
}

} // namespace idr::canon
