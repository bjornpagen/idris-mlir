// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Output of a list (idr.io.put_list) takes one step of the list it meets: a
// constant list, the nil among them, is written as the string it folds to,
// and a cell as its element before the rest. Each step creates ops, which a
// folder could not.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

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
// cell with another use stays, and is written as it is walked. The list's
// cell is the constructor with two fields, and its first field is the
// element, a character or a string: the constructor's verifier makes the
// field the declaration's, so the declaration is not looked up.
struct PutListOfCons : OpRewritePattern<PutListOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(PutListOp op, PatternRewriter &rewriter) const final {
    auto cell = op.getList().getDefiningOp<ConOp>();
    if (!cell || !cell->hasOneUse() || cell.getFields().size() != 2)
      return failure();
    Value head = cell.getFields()[0];
    Type element = head.getType();
    if (!isa<StrType>(element) && element != rewriter.getI32Type())
      return failure();
    Location loc = op.getLoc();
    Type world = op.getNext().getType();
    Value written = isa<StrType>(element)
                        ? PutStrOp::create(rewriter, loc, world, head, op.getWorld()).getNext()
                        : PutCharOp::create(rewriter, loc, world, head, op.getWorld()).getNext();
    rewriter.replaceOpWithNewOp<PutListOp>(op, world, cell.getFields()[1], written);
    rewriter.eraseOp(cell);
    return success();
  }
};

} // namespace

namespace idr::canon {

void addPutListPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<PutListOfConstant, PutListOfCons>(context);
}

} // namespace idr::canon
