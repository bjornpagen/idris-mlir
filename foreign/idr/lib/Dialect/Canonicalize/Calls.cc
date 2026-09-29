// The dialect's patterns on func.call.

#include "Facts/Facts.h"
#include "idr/Idr.h"

#include "mlir/IR/PatternMatch.h"

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

// A string that the callee writes before anything else it does with the world
// (idr.writes_first, from idr-effects) is written by the caller instead, into
// the world it passes, and the callee gets the empty string: a string built
// at runtime is then written piece by piece where it is built, rather than
// passed on. A recursion that appends to such a string before passing it to
// itself writes each piece as it goes. A string that is a constant or a
// parameter stays: nothing is built for it. Each rewrite leaves a constant
// where a built string was, so it happens once per operand.
struct WriteBeforeCall : OpRewritePattern<func::CallOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(func::CallOp call, PatternRewriter &rewriter) const final {
    auto callee = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
    if (!callee || callee.getNumArguments() != call.getNumOperands())
      return failure();
    std::optional<unsigned> world;
    for (auto [index, type] : llvm::enumerate(callee.getArgumentTypes()))
      if (isa<WorldType>(type)) {
        if (world)
          return failure();
        world = static_cast<unsigned>(index);
      }
    if (!world)
      return failure();
    for (unsigned index = 0; index < call.getNumOperands(); ++index) {
      Operation *built = call.getOperand(index).getDefiningOp();
      if (!built || built->hasTrait<OpTrait::ConstantLike>() ||
          !callee.getArgAttr(index, "idr.writes_first"))
        continue;
      rewriter.setInsertionPoint(call);
      Value text = call.getOperand(index);
      Value before = call.getOperand(*world);
      Value written = PutStrOp::create(rewriter, call.getLoc(), before.getType(), text, before);
      Value empty = ConstantOp::create(rewriter, call.getLoc(), text.getType(),
                                       rewriter.getStringAttr(""));
      rewriter.modifyOpInPlace(call, [&] {
        call->setOperand(index, empty);
        call->setOperand(*world, written);
      });
      return success();
    }
    return failure();
  }
};

} // namespace

void IdrDialect::getCanonicalizationPatterns(RewritePatternSet &results) const {
  results.add<RemoveUnusedCall, WriteBeforeCall>(getContext());
}
