// Lowering of the ops that count references: calls of the runtime, which
// LTO inlines. In JIT mode every cell is persistent, so counting does
// nothing, and a take never yields a cell.

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

// The token's cell with a new header and fields, or a new cell when the
// token is null.
struct LowerReuse : IdrPattern<ReuseOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ReuseOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    const Cell &layout = layouts.box(ctor);
    CellInfo info = layout.info;
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

// A sum's fields are its slots, and move as they are. A box's fields are
// loaded; when the box held the only reference to its cell they move out of
// it and the token is the cell, otherwise they each get one more
// reference, the box drops its own, and the token is null.
struct LowerTake : IdrPattern<TakeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TakeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type type = op.getValue().getType();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    ValueRange value = adaptor.getValue();
    SmallVector<SmallVector<Value>> out;
    if (auto data = dyn_cast<DataType>(type)) {
      const SumLayout &layout = layouts.sum(data.getName().getAttr());
      for (const auto &slots : layout.fields.find(ctor.getSymName())->second)
        out.push_back(llvm::map_to_vector(
            slots, [&](unsigned slot) { return value[layout.offset() + slot]; }));
      rewriter.replaceOpWithMultiple(op, std::move(out));
      return success();
    }
    Value cell = value.front();
    const Cell &layout = layouts.box(ctor);
    SmallVector<Value> components;
    for (const auto &slots : layout.fields) {
      out.push_back(runtime.load(rewriter, loc, cell, slots));
      llvm::append_range(components, out.back());
    }
    SmallVector<bool> counted;
    for (Type fieldType : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
      llvm::append_range(counted, layouts.counted(fieldType));
    Type ptr = cell.getType();
    auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                    runtime.exclusive(rewriter, loc, cell),
                                    /*withElseRegion=*/true);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.inc(rewriter, loc, components, counted);
      runtime.dec(rewriter, loc, cell, {true});
      scf::YieldOp::create(rewriter, loc, runtime.null(rewriter, loc, ptr));
    }
    out.insert(out.begin(), SmallVector<Value>{choose.getResult(0)});
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

} // namespace

void populateCountingPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerInc, LowerDec, LowerReuse, LowerTake>(converter, patterns.getContext(),
                                                          layouts, runtime);
}

} // namespace idr::lower
