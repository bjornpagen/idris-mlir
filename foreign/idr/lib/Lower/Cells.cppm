// idr.lower:cells: the patterns of cells and unboxed sums, and of the
// changes of grade and kind that have no runtime form.

export module idr.lower:cells;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :buildBox;
import :idrPattern;
import :runtime;
import :stackCell;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// An unboxed constructor is its tag and its components in their slots, an
// empty value in the counted slots it does not use and poison in the
// others. A boxed one is a new cell holding its tag and components.
struct LowerCon : IdrPattern<ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(op, op.getCtor());
    if (isa<BoxType>(unrestricted(op.getType()))) {
      // idr-stack: a cell that never outlives its frame is a slot of it.
      Value box = buildBox(rewriter, loc, layouts, runtime, ctor,
                           stackCell(rewriter, loc, op, layouts, runtime), adaptor.getFields());
      rewriter.replaceOp(op, box);
      return success();
    }
    const layout::SumLayout &layout =
        layouts.sum(cast<DataType>(unrestricted(op.getType())).getName().getAttr());
    SmallVector<Value> slots(layout.slots.size());
    const auto &fields = layout.fields.find(ctor.getSymName())->second;
    for (auto [field, values] : llvm::zip_equal(fields, adaptor.getFields()))
      for (auto [slot, value] : llvm::zip_equal(field, values))
        slots[slot] = value;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(arith::ConstantOp::create(
          rewriter, loc, IntegerAttr::get(layout.tag, static_cast<int64_t>(ctor.getTag()))));
    for (auto [slot, value] : llvm::enumerate(slots))
      out.push_back(value                  ? value
                    : layout.counted[slot] ? runtime.null(rewriter, loc, layout.slots[slot])
                                           : ub::PoisonOp::create(rewriter, loc, layout.slots[slot])
                                                 .getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// The tag slot, extended to i64, or 0 for one constructor; a
// box's tag is in its header.
struct LowerTag : IdrPattern<TagOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TagOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto i64 = rewriter.getI64Type();
    if (isa<BoxType>(unrestricted(op.getValue().getType()))) {
      Value tag = runtime.loadTag(rewriter, loc, adaptor.getValue().front());
      rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, i64, tag);
      return success();
    }
    const layout::SumLayout &layout =
        layouts.sum(cast<DataType>(unrestricted(op.getValue().getType())).getName().getAttr());
    if (!layout.tag)
      rewriter.replaceOp(op, constantI64(rewriter, loc, 0));
    else
      rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, i64, adaptor.getValue().front());
    return success();
  }
};

// The components of a field from its constructor's slots, or
// loaded from a box's cell.
struct LowerField : IdrPattern<FieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(FieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto index = static_cast<unsigned>(op.getIndex());
    Type type = unrestricted(op.getValue().getType());
    if (isa<BoxType>(type)) {
      CtorOp ctor = lookupCtor(lookupData(op, type), op.getCtor());
      rewriter.replaceOpWithMultiple(
          op, {runtime.load(rewriter, op.getLoc(), adaptor.getValue().front(),
                            layouts.box(ctor).fields[index])});
      return success();
    }
    const layout::SumLayout &layout = layouts.sum(cast<DataType>(type).getName().getAttr());
    ValueRange values = adaptor.getValue();
    SmallVector<Value> out;
    for (unsigned slot : layout.fields.find(op.getCtor())->second[index])
      out.push_back(values[layout.offset() + slot]);
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// Strings, bigs, boxes and closures are static data; an unboxed
// constant is its components.
struct LowerConstant : IdrPattern<ConstantOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConstantOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(
        op, {runtime.constant(rewriter, op.getLoc(), op.getValue(), op.getType())});
    return success();
  }
};

// Linearity has no runtime form: entering and using a linear value is the
// value itself. Nor has non-negativity: a natural is the Integer it is.
template <typename OpT>
struct LowerAsItself : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange value = adaptor.getOperands().front();
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(value.begin(), value.end())});
    return success();
  }
};

// A pending field is stored as poison: it is written through its
// destination before anything reads it.
struct LowerPending : IdrPattern<PendingOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(PendingOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> out;
    for (Type type : layouts.components(op.getType()))
      out.push_back(ub::PoisonOp::create(rewriter, op.getLoc(), type));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A destination is the address of its field's word in the cell.
struct LowerDestOf : IdrPattern<DestOfOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestOfOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    CtorOp ctor = lookupCtor(lookupData(op, op.getValue().getType()), op.getCtor());
    const auto &slots = layouts.box(ctor).fields[static_cast<unsigned>(op.getIndex())];
    rewriter.replaceOp(op, runtime.address(rewriter, op.getLoc(), adaptor.getValue().front(),
                                           slots.front()));
    return success();
  }
};

struct LowerDestWrite : IdrPattern<DestWriteOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestWriteOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.storeWord(rewriter, op.getLoc(), adaptor.getDest().front(),
                      adaptor.getValue().front());
    rewriter.eraseOp(op);
    return success();
  }
};

// Poison of an idr type becomes poison of each component, but for the
// counted ones, which are empty: poison may still be dropped, as what a
// function nobody reads is passed, or what idr-tail-loops forwards on the
// path it does not take.
struct LowerPoison : IdrPattern<ub::PoisonOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ub::PoisonOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> out;
    for (auto [type, isCounted] :
         llvm::zip_equal(layouts.components(op.getType()), layouts.counted(op.getType())))
      out.push_back(isCounted ? runtime.null(rewriter, op.getLoc(), type)
                              : ub::PoisonOp::create(rewriter, op.getLoc(), type).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A select of an idr value selects each of its components.
struct LowerSelect : IdrPattern<arith::SelectOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(arith::SelectOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Value cond = adaptor.getCondition().front();
    SmallVector<Value> out;
    for (auto [a, b] : llvm::zip_equal(adaptor.getTrueValue(), adaptor.getFalseValue()))
      out.push_back(arith::SelectOp::create(rewriter, op.getLoc(), cond, a, b));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

} // namespace

// The patterns of cells and unboxed sums: constructors, their tags and
// fields, constants, destinations, and what poison and select make of an
// idr value.
export void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCon, LowerTag, LowerField, LowerConstant, LowerPoison, LowerSelect,
               LowerPending, LowerDestOf, LowerDestWrite, LowerAsItself<LinEnterOp>,
               LowerAsItself<LinUseOp>, LowerAsItself<NatToBigOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
