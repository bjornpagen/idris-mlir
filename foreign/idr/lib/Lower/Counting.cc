// Lowering of the ops that count references: calls of the runtime, which
// LTO inlines. In JIT mode every cell is persistent, so counting does
// nothing, and a take never yields a cell.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

namespace {

// One more reference for each counted component. Static data holds no
// count, so a reference to it is its address: nothing runs. The value is
// read as lowered, since the constant that made it static is gone by now.
struct LowerDup : IdrPattern<DupOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DupOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange components = adaptor.getValue();
    SmallVector<bool> counted = layouts.counted(op.getValue().getType());
    for (auto [i, component] : llvm::enumerate(components))
      counted[i] = counted[i] && !Runtime::isStatic(component);
    runtime.inc(rewriter, op.getLoc(), components, counted);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(components)});
    return success();
  }
};

// One less for each counted component; a token's memory is freed.
struct LowerDrop : IdrPattern<DropOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DropOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type type = op.getValue().getType();
    if (isa<TokenType>(unrestricted(type))) {
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
    Value where;
    if (isExclusive(op.getToken().getType())) {
      // An exclusive token is the cell, certainly: no test.
      runtime.storeHeader(rewriter, loc, token, info);
      where = token;
    } else {
      Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, token,
                                         runtime.null(rewriter, loc, ptr));
      auto choose =
          scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, runtime.allocate(rewriter, loc, layout.size, info));
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.storeHeader(rewriter, loc, token, info);
      scf::YieldOp::create(rewriter, loc, token);
      where = choose.getResult(0);
    }
    Value cell = buildBox(rewriter, loc, layouts, runtime, ctor, where, adaptor.getFields());
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
    Type type = unrestricted(op.getValue().getType());
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
    // A constructor without fields is its atom: nothing is loaded, and
    // nothing is anyone's to free.
    if (!op.getToken()) {
      rewriter.eraseOp(op);
      return success();
    }
    const Cell &layout = layouts.box(ctor);
    SmallVector<Value> components;
    for (const auto &slots : layout.fields) {
      out.push_back(runtime.load(rewriter, loc, cell, slots));
      llvm::append_range(components, out.back());
    }
    Value token = cell;
    // An exclusive value alone reaches its cell: its fields move out, and
    // the cell is the token, with no test.
    if (!isExclusive(op.getValue().getType())) {
      SmallVector<bool> counted;
      for (Type fieldType : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
        llvm::append_range(counted, layouts.counted(fieldType));
      Type ptr = cell.getType();
      auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                      runtime.exclusive(rewriter, loc, cell),
                                      /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.inc(rewriter, loc, components, counted);
      runtime.dec(rewriter, loc, cell, {true});
      scf::YieldOp::create(rewriter, loc, runtime.null(rewriter, loc, ptr));
      token = choose.getResult(0);
    }
    out.insert(out.begin(), SmallVector<Value>{token});
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

// Forgetting exclusivity has no runtime form: the value is itself.
struct LowerShare : IdrPattern<ShareOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ShareOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(adaptor.getValue())});
    return success();
  }
};

// A view has no runtime form: it is the value itself.
struct LowerBorrow : IdrPattern<BorrowOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BorrowOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(adaptor.getValue())});
    return success();
  }
};

} // namespace

void populateCountingPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerDup, LowerDrop, LowerBorrow, LowerShare, LowerReuse, LowerTake>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
