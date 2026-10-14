// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Output and the first character of a string being built: the DRR patterns
// of Canonicalize.td, and the empty string, which DRR cannot match. Output
// of a list (idr.io.put_list) takes one step of the list it meets
// (PutList.cpp).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

#include "IdrCanonicalize.inc"

// Writing the empty string writes nothing. A folder of put_str would say
// the same; the op declares none.
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

namespace idr::canon {

void addPutStrPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble, Idr_PutStrOfPack, Idr_PutStrOfConcat, PutStrOfEmpty>(
      context);
}

void addStrHeadPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble, Idr_HeadOfCheckedCons,
              Idr_HeadOfCheckedShowInt, Idr_HeadOfCheckedShowDouble>(context);
}

} // namespace idr::canon
