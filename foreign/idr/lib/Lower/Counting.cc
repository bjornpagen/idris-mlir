// Lowering of the ops that count references: calls of the runtime, which
// LTO inlines. In JIT mode every cell is persistent, so counting does
// nothing, and a reset never yields a cell.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

namespace {

// One more reference for each counted component.
struct LowerInc : IdrPattern<IncOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(IncOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.inc(rewriter, op.getLoc(), adaptor.getValue(), layouts.counted(op.getValue().getType()));
    rewriter.eraseOp(op);
    return success();
  }
};

// One less for each counted component; a token's memory is freed.
struct LowerDec : IdrPattern<DecOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DecOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type type = op.getValue().getType();
    if (isa<TokenType>(type)) {
      if (!runtime.isJit())
        runtime.call(rewriter, op.getLoc(), "idris_rt_free_cell", Type(),
                     adaptor.getValue().front());
    } else {
      runtime.dec(rewriter, op.getLoc(), adaptor.getValue(), layouts.counted(type));
    }
    rewriter.eraseOp(op);
    return success();
  }
};

// The cell when the box held its last reference, else null.
struct LowerReset : IdrPattern<ResetOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ResetOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type ptr = LLVM::LLVMPointerType::get(rewriter.getContext());
    Value token = runtime.isJit()
                      ? runtime.null(rewriter, loc, ptr)
                      : runtime.call(rewriter, loc, "idris_rt_reset", ptr,
                                     adaptor.getValue().front());
    rewriter.replaceOp(op, token);
    return success();
  }
};

// The token's cell with a new header and fields, or a new cell when the
// token is null.
struct LowerReuse : IdrPattern<ReuseOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ReuseOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    const Cell &layout = layouts.box(ctor);
    uint32_t info = cellInfo(static_cast<uint32_t>(ctor.getTag()), layout.objs, CellKind::Box);
    Value token = adaptor.getToken().front();
    Type ptr = token.getType();
    Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, token,
                                       runtime.null(rewriter, loc, ptr));
    auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, runtime.allocate(rewriter, loc, layout.size, info));
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.storeHeader(rewriter, loc, token, info);
      scf::YieldOp::create(rewriter, loc, token);
    }
    Value cell = buildBox(rewriter, loc, layouts, runtime, ctor, choose.getResult(0),
                          adaptor.getFields());
    rewriter.replaceOp(op, cell);
    return success();
  }
};

} // namespace

void populateCountingPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerInc, LowerDec, LowerReset, LowerReuse>(converter, patterns.getContext(),
                                                           layouts, runtime);
}

} // namespace idr::lower
