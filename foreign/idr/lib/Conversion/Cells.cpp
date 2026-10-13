// The patterns of cells and unboxed sums, and of the changes of grade and
// kind that have no runtime form.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the size of its words is a macro.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A box's cell: count 1 and its info word, then its fields' components
// stored at their offsets.
Value buildBox(OpBuilder &b, Location loc, const Layouts &layouts, Runtime &runtime, CtorOp ctor,
               Value cell, ArrayRef<ValueRange> fields) {
  const layout::Cell &layout = layouts.box(ctor);
  if (!cell)
    cell = runtime.allocate(b, loc, layout.size, layout.info);
  for (auto [slots, values] : llvm::zip_equal(layout.fields, fields))
    runtime.store(b, loc, cell, slots, values);
  return cell;
}

// The cell of `con`, a box's constructor that idr-stack marked, before its
// fields: a slot in the entry block of the function that holds it, one slot
// per con, allocated once per frame however often the con runs, so LLVM may
// keep it in registers when it stays in the function. Its header, written
// where the con runs, is count 1 and the box's info with the stack mark
// (IDRIS_RT_STACK_CELL): counting works on it as on any cell, but when its
// count reaches 0 its memory is not freed, and it is never exclusive, so no
// reset reuses it for a value that could outlive the frame. Null when the
// con is not marked.
Value stackCell(OpBuilder &b, Location loc, ConOp con, CtorOp ctor, const Layouts &layouts,
                Runtime &runtime) {
  if (!IdrDialect::StackAttrHelper(con->getContext()).isAttrPresent(con))
    return {};
  const layout::Cell &layout = layouts.box(ctor);
  Value slot;
  {
    OpBuilder::InsertionGuard guard(b);
    Operation *scope = con->getParentWithTrait<OpTrait::AutomaticAllocationScope>();
    b.setInsertionPointToStart(&scope->getRegion(0).front());
    slot = LLVM::AllocaOp::create(b, loc, ptrType(b.getContext()),
                                  LLVM::LLVMArrayType::get(b.getI8Type(), layout.size),
                                  i64Constant(b, loc, 1), /*alignment=*/IDRIS_RT_WORD_BYTES);
  }
  runtime.storeHeader(b, loc, slot, layout.info.onStack());
  return slot;
}

// An unboxed constructor is its tag and its components in their slots, and
// zero in the slots it does not use: empty where the slot is counted, so
// that counting the sum counts each of its slots, as static data has it. A
// boxed one is a new cell holding its tag and components, at its sum's
// size: a memo cell's fits every state it is written in.
struct LowerCon : IdrPattern<ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp ctor = lookupCtor(runtime.symbols(), op.getCtor());
    if (isa<BoxType>(unrestricted(op.getType()))) {
      // idr-stack: a cell that never outlives its frame is a slot of it.
      Value cell = stackCell(rewriter, loc, op, ctor, layouts, runtime);
      Value box = buildBox(rewriter, loc, layouts, runtime, ctor, cell, adaptor.getFields());
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
      out.push_back(arith::ConstantIntOp::create(rewriter, loc, layout.tag,
                                                 static_cast<int64_t>(ctor.getTag())));
    for (auto [slot, value] : llvm::enumerate(slots))
      out.push_back(value ? value
                          : LLVM::ZeroOp::create(rewriter, loc, layout.slots[slot]).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// The tag slot, extended to i64, or 0 for one constructor; a box's tag is
// in its header.
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
      rewriter.replaceOpWithNewOp<arith::ConstantIntOp>(op, 0, 64);
    else
      rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, i64, adaptor.getValue().front());
    return success();
  }
};

// The components of a field from its constructor's slots, or loaded from a
// box's cell.
struct LowerField : IdrPattern<FieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(FieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto index = static_cast<unsigned>(op.getIndex());
    Type type = unrestricted(op.getValue().getType());
    if (isa<BoxType>(type)) {
      CtorOp ctor = lookupCtor(lookupData(runtime.symbols(), type), op.getCtor());
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

// Strings, bigs and boxes, memo cells among them, are static data; an
// unboxed constant is its components.
struct LowerConstant : IdrPattern<ConstantOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConstantOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(
        op, {runtime.constant(rewriter, op.getLoc(), op.getValue(), op.getType())});
    return success();
  }
};

// A pending field has no value until it is written through its
// destination, before anything reads it. Until then its components are
// zero, so that the cell it is stored in is whole: an object slot holds an
// empty reference.
struct LowerPending : IdrPattern<PendingOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(PendingOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> out;
    for (Type type : layouts.components(op.getType()))
      out.push_back(LLVM::ZeroOp::create(rewriter, op.getLoc(), type));
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A destination is the address of its field's word in the cell.
struct LowerDestOf : IdrPattern<DestOfOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestOfOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    CtorOp ctor =
        lookupCtor(lookupData(runtime.symbols(), op.getValue().getType()), op.getCtor());
    const auto &slots = layouts.box(ctor).fields[static_cast<unsigned>(op.getIndex())];
    rewriter.replaceOp(op, at(rewriter, op.getLoc(), adaptor.getValue().front(),
                              slots.front().offset));
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
      out.push_back(isCounted ? nullComponent(rewriter, op.getLoc(), type)
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
void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCon, LowerTag, LowerField, LowerConstant, LowerPoison, LowerSelect,
               LowerPending, LowerDestOf, LowerDestWrite, LowerAsItself<LinEnterOp>,
               LowerAsItself<LinUseOp>, LowerAsItself<NatToBigOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
