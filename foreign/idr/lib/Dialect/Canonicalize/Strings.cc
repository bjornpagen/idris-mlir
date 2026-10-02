// Output and the first character of a string being built: the DRR patterns
// of Canonicalize.td, and the empty string, which DRR cannot match. Output
// of a list (idr.io.put_list) takes one step of the list it meets: a
// constant list, the nil among them, is written as the string it folds to,
// and a cell as its element before the rest.

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

// Writing a constant list writes the string it packs or concatenates to,
// which folding builds, and the nil writes nothing. Compile-time evaluation
// can make the list a constant after output of its pack became
// idr.io.put_list.
struct PutListOfConstant : OpRewritePattern<PutListOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(PutListOp op, PatternRewriter &rewriter) const final {
    Attribute list;
    if (!matchPattern(op.getList(), m_Constant(&list)))
      return failure();
    auto text = dyn_cast_or_null<StringAttr>(stringOfList(getContext(), list));
    if (!text)
      return failure();
    if (text.getValue().empty()) {
      rewriter.replaceOp(op, op.getWorld());
      return success();
    }
    Value s = ConstantOp::create(rewriter, op.getLoc(), StrType::get(getContext()), text);
    rewriter.replaceOpWithNewOp<PutStrOp>(op, op.getNext().getType(), s, op.getWorld());
    return success();
  }
};

// Writing a cell writes its element, as put_char or put_str does, then the
// rest of the list; the cell, built only to be written, is not built. A
// cell with another use stays, and is written as it is walked.
struct PutListOfCons : OpRewritePattern<PutListOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(PutListOp op, PatternRewriter &rewriter) const final {
    auto cell = op.getList().getDefiningOp<ConOp>();
    Type element = op.getElementType();
    if (!cell || !cell->hasOneUse() || cell.getFields().size() != 2 ||
        cell.getFields()[0].getType() != element)
      return failure();
    Location loc = op.getLoc();
    Type world = op.getNext().getType();
    Value head = cell.getFields()[0];
    Value written = isa<StrType>(element)
                        ? PutStrOp::create(rewriter, loc, world, head, op.getWorld()).getNext()
                        : PutCharOp::create(rewriter, loc, world, head, op.getWorld()).getNext();
    rewriter.replaceOpWithNewOp<PutListOp>(op, world, cell.getFields()[1], written);
    rewriter.eraseOp(cell);
    return success();
  }
};

} // namespace

bool idr::writtenInPieces(Value str) {
  Operation *builder = str.getDefiningOp();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(builder))
    return true;
  return isa_and_nonnull<StrPackOp, StrConcatOp>(builder) && str.hasOneUse();
}

void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_PutStrOfAppend, Idr_PutStrOfCons, Idr_PutStrOfFromChar, Idr_PutStrOfShowInt,
              Idr_PutStrOfShowDouble, Idr_PutStrOfPack, Idr_PutStrOfConcat, PutStrOfEmpty>(context);
}

void PutListOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<PutListOfConstant, PutListOfCons>(context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<Idr_HeadOfCons, Idr_HeadOfShowInt, Idr_HeadOfShowDouble>(context);
}
