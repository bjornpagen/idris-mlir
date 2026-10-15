// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
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

using namespace mlir;

namespace idr::conversion {

namespace {

// A box's cell of the constructor `tag`: its header and the words after it,
// then its fields' components stored at their offsets.
Value buildBox(OpBuilder &b, Location loc, Runtime &runtime, const layout::Cell &layout,
               unsigned tag, Value cell, ArrayRef<SmallVector<Value>> fields) {
  if (!cell)
    cell = runtime.allocate(b, loc, layout, tag);
  for (auto [slots, values] : llvm::zip_equal(layout.fields, fields))
    runtime.store(b, loc, cell, cellAlignment(), slots, values);
  return cell;
}

// The cell of `con`, a box's constructor idr-stack put on the stack (its
// `stack` property), before its fields: a slot in the entry block of the
// function that holds it, one slot per con, allocated once per frame however
// often the con runs, so LLVM may keep it in registers when it stays in the
// function. Its header, written
// where the con runs, is count 1 and the box's info with the stack mark
// (IDRIS_RT_STACK_CELL): counting works on it as on any cell, but when its
// count reaches 0 its memory is not freed, and it is never exclusive, so no
// reset reuses it for a value that could outlive the frame. Null for a
// con on the heap.
Value stackCell(OpBuilder &b, Location loc, ConOp con, const layout::Cell &layout,
                unsigned tag, Runtime &runtime) {
  if (!con.getStack())
    return {};
  Value slot;
  {
    OpBuilder::InsertionGuard guard(b);
    Operation *scope = con->getParentWithTrait<OpTrait::AutomaticAllocationScope>();
    b.setInsertionPointToStart(&scope->getRegion(0).front());
    slot = LLVM::AllocaOp::create(b, loc, ptrType(b.getContext()),
                                  LLVM::LLVMArrayType::get(b.getI8Type(), layout.size),
                                  i64Constant(b, loc, 1), cellAlignment());
  }
  runtime.storeHeader(b, loc, slot, layout, tag, layout.info.onStack());
  return slot;
}

// An unboxed constructor is its tag and its components in their slots, and
// zero in the slots it does not use: empty where the slot is counted, so
// that counting the sum counts each of its slots, as static data has it. A
// boxed one is a new cell holding its tag and components, at its sum's
// size: a memo cell's fits every state it is written in; and the
// destination of each of its holes, the address of the hole's word.
struct LowerCon : IdrPattern<ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    unsigned tag = op.getTag();
    if (isBoxed(op.getResult().getType())) {
      // idr-stack: a cell that never outlives its frame is a slot of it.
      const layout::Cell &cell = layouts.box(data, tag);
      Value slot = stackCell(rewriter, loc, op, cell, tag, runtime);
      Value box =
          buildBox(rewriter, loc, runtime, cell, tag, slot,
                   fieldsOf(rewriter, loc, cell, op.getHoles(), adaptor.getFields()));
      SmallVector<SmallVector<Value>> out{{box}};
      llvm::append_range(out, destsOf(rewriter, loc, box, cell, op.getHoles()));
      rewriter.replaceOpWithMultiple(op, std::move(out));
      return success();
    }
    const layout::SumLayout &layout = layouts.sum(data);
    SmallVector<Value> slots(layout.slots.size());
    for (auto [field, values] : llvm::zip_equal(layout.fields[tag], adaptor.getFields()))
      for (auto [slot, value] : llvm::zip_equal(field, values))
        slots[slot] = value;
    SmallVector<Value> out;
    if (layout.tag)
      out.push_back(
          arith::ConstantIntOp::create(rewriter, loc, layout.tag, static_cast<int64_t>(tag)));
    for (auto [slot, value] : llvm::enumerate(slots))
      out.push_back(value ? value
                          : LLVM::ZeroOp::create(rewriter, loc, layout.slots[slot]).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// The tag slot, extended to i64, or 0 for one constructor; a box's tag is
// in its header, and its group's word where its sum has one.
struct LowerTag : IdrPattern<TagOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TagOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto i64 = rewriter.getI64Type();
    DataType data = dataTypeOf(op.getValue().getType());
    if (isBoxed(op.getValue().getType())) {
      rewriter.replaceOp(op,
                         runtime.loadTag(rewriter, loc, adaptor.getValue().front(), data, layouts));
      return success();
    }
    const layout::SumLayout &layout = layouts.sum(data);
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
    unsigned tag = op.getTag();
    DataType data = op.getDataType();
    if (isBoxed(op.getValue().getType())) {
      rewriter.replaceOpWithMultiple(
          op, {runtime.load(rewriter, op.getLoc(), adaptor.getValue().front(), cellAlignment(),
                            layouts.box(data, tag).fields[index])});
      return success();
    }
    const layout::SumLayout &layout = layouts.sum(data);
    ValueRange values = adaptor.getValue();
    SmallVector<Value> out;
    for (unsigned slot : layout.fields[tag][index])
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

// A hole's value, written once through its destination.
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

SmallVector<SmallVector<Value>> fieldsOf(OpBuilder &b, Location loc, const layout::Cell &cell,
                                         ArrayRef<int32_t> holes, ArrayRef<ValueRange> given) {
  SmallVector<SmallVector<Value>> fields;
  const ValueRange *next = given.begin();
  for (auto [index, slots] : llvm::enumerate(cell.fields)) {
    if (!llvm::binary_search(holes, static_cast<int32_t>(index))) {
      fields.push_back(SmallVector<Value>(*next++));
      continue;
    }
    fields.push_back(llvm::map_to_vector(slots, [&](const layout::Slot &slot) -> Value {
      return LLVM::ZeroOp::create(b, loc, slot.type);
    }));
  }
  return fields;
}

SmallVector<SmallVector<Value>> destsOf(OpBuilder &b, Location loc, Value cell,
                                        const layout::Cell &layout, ArrayRef<int32_t> holes) {
  return llvm::map_to_vector(holes, [&](int32_t hole) {
    return SmallVector<Value>{
        at(b, loc, cell, layout.fields[static_cast<unsigned>(hole)].front().offset)};
  });
}

// The patterns of cells and unboxed sums: constructors, their tags and
// fields, constants, the writes of holes, and what poison and select make
// of an idr value.
void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCon, LowerTag, LowerField, LowerConstant, LowerPoison, LowerSelect,
               LowerDestWrite, LowerAsItself<LinEnterOp>, LowerAsItself<LinUseOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
