// Lowering of the ops that count references: calls of the runtime, which
// LTO inlines. In JIT mode every cell is persistent, so counting does
// nothing, and a take never yields a cell.

#include "Lower/Patterns.h"

using namespace mlir;

namespace idr::lower {

namespace {

// The value a field was given on as: through the changes of grade that
// have no runtime form (idr.share, idr.lin.enter, idr.lin.use) to the
// value that holds the reference.
Value moved(Value value) {
  while (Operation *def = value.getDefiningOp()) {
    if (!isa<ShareOp, LinEnterOp, LinUseOp>(def))
      break;
    value = def->getOperand(0);
  }
  return value;
}

} // namespace

// A field a reuse gives back as its token's take gave it is in the cell
// already, with the reference the cell held all along: the take moved it
// out without a count and the reuse moves it in without one, so the owned
// stage counts nothing for it, and nothing need be stored for it here
// (Lean's ExpandResetReuse; Perceus's reuse specialization). The fact is
// the identity of two values of the owned stage, which the conversion
// loses as it goes: it replaces each op as it meets it, so by the time a
// reuse is converted the take that made its token is a test and some
// loads. So it is read from every reuse before the conversion starts.
Fields::Fields(ModuleOp module) {
  module.walk([&](ReuseOp reuse) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    if (!take || take.getCtor() != reuse.getCtor())
      return;
    SmallVector<bool> &mask = keptFields[reuse];
    for (auto [field, taken] : llvm::zip_equal(reuse.getFields(), take.getFields()))
      mask.push_back(moved(field) == taken);
  });
}

ArrayRef<bool> Fields::kept(ReuseOp reuse) const {
  auto it = keptFields.find(reuse);
  return it == keptFields.end() ? ArrayRef<bool>() : ArrayRef<bool>(it->second);
}

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

// The token's cell, or a new cell when the token is null, holding the
// constructor. A reuse of the constructor its token's take took apart
// finds the header in the cell already, and every field it gives back as
// taken (Fields): those are stored into a new cell only, and the header is
// left as it is. On rbtree's `Node Red (ins l) k v r` that is one store of
// five and no header write where the cell is the node's own.
struct LowerReuse : IdrPattern<ReuseOp> {
  LowerReuse(const TypeConverter &converter, MLIRContext *ctx, Layouts &layouts, Runtime &runtime,
             const Fields &fields)
      : IdrPattern(converter, ctx, layouts, runtime), fields(fields) {}

  LogicalResult matchAndRewrite(ReuseOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    const Cell &layout = layouts.box(ctor);
    CellInfo info = layout.info;
    ArrayRef<bool> kept = fields.kept(op);
    // The fields `cell` holds already when `held`, the others otherwise.
    auto store = [&](OpBuilder &b, Value cell, bool held) {
      for (auto [index, slots, values] : llvm::enumerate(layout.fields, adaptor.getFields()))
        if ((!kept.empty() && kept[index]) == held)
          runtime.store(b, loc, cell, slots, values);
    };
    Value token = adaptor.getToken().front();
    Type ptr = token.getType();
    Value where;
    if (isExclusive(op.getToken().getType())) {
      // An exclusive token is the cell, certainly: no test.
      if (kept.empty())
        runtime.storeHeader(rewriter, loc, token, info);
      where = token;
    } else {
      Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, token,
                                         runtime.null(rewriter, loc, ptr));
      auto choose =
          scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      Value fresh = runtime.allocate(rewriter, loc, layout.size, info);
      store(rewriter, fresh, /*held=*/true);
      scf::YieldOp::create(rewriter, loc, fresh);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      if (kept.empty())
        runtime.storeHeader(rewriter, loc, token, info);
      scf::YieldOp::create(rewriter, loc, token);
      where = choose.getResult(0);
    }
    store(rewriter, where, /*held=*/false);
    rewriter.replaceOp(op, where);
    return success();
  }

  const Fields &fields;
};

// A sum's fields are its slots, and move as they are. A box's fields are
// loaded; when the box held the only reference to its cell they move out of
// it and the token is the cell, otherwise they each get one more
// reference, the box drops its own, and the token is null. A field nothing
// wants, whose one use is an idr.drop, dies with the box (Perceus's drop
// specialization, with the dups and drops fused): where the box held the
// only reference the field's own is dropped here, and where the box was
// shared nothing happens to the field, instead of a reference taken for it
// and given up again.
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
    SmallVector<DropOp> drops;
    for (Value field : op.getFields())
      drops.push_back(field.hasOneUse() ? dyn_cast<DropOp>(*field.user_begin()) : DropOp());
    // The components of the fields that move on and of those that die
    // here, each with whether it is counted.
    SmallVector<Value> moving, dying;
    SmallVector<bool> movingCounted, dyingCounted;
    for (auto [index, slots, fieldType] :
         llvm::enumerate(layout.fields, ctor.getFieldTypes().getAsValueRange<TypeAttr>())) {
      out.push_back(runtime.load(rewriter, loc, cell, slots));
      bool dies = drops[index] != nullptr;
      llvm::append_range(dies ? dying : moving, out.back());
      llvm::append_range(dies ? dyingCounted : movingCounted, layouts.counted(fieldType));
    }
    Value token = cell;
    // An exclusive value alone reaches its cell: its fields move out, and
    // the cell is the token, with no test.
    if (isExclusive(op.getValue().getType())) {
      runtime.dec(rewriter, loc, dying, dyingCounted);
    } else {
      Type ptr = cell.getType();
      auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                      runtime.exclusive(rewriter, loc, cell),
                                      /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      runtime.dec(rewriter, loc, dying, dyingCounted);
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.inc(rewriter, loc, moving, movingCounted);
      runtime.dec(rewriter, loc, cell, {true});
      scf::YieldOp::create(rewriter, loc, runtime.null(rewriter, loc, ptr));
      token = choose.getResult(0);
    }
    for (DropOp drop : drops)
      if (drop)
        rewriter.eraseOp(drop);
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
                              Layouts &layouts, Runtime &runtime, const Fields &fields) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerDup, LowerDrop, LowerBorrow, LowerShare, LowerTake>(converter, ctx, layouts,
                                                                       runtime);
  patterns.add<LowerReuse>(converter, ctx, layouts, runtime, fields);
}

} // namespace idr::lower
