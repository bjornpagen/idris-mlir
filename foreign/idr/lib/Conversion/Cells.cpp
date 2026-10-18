// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of cells and unboxed sums: a cell's producers, each of which
// writes the cell's header, and its init, which writes its fields; the
// constructors that build no cell; and the reads of tags and fields.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Fields.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The layout of a cell of `type`: its box's data type's cell of the
// constructor the type names.
const layout::Cell &cellOf(const Layouts &layouts, CellType type) {
  return layouts.box(type.getBox().getData()).cell(type.getTag());
}

// The components each field of a constructor stores in a cell laid out as
// `cell`: those `given`, in field order, and zero for each of `holes`, so
// that the cell is whole until the hole's destination is written, an
// object slot holding an empty reference.
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

// The destination of each of `holes` of a constructor built in `cell`, laid
// out as `layout`: the address of the hole's word.
SmallVector<SmallVector<Value>> destsOf(OpBuilder &b, Location loc, Value cell,
                                        const layout::Cell &layout, ArrayRef<int32_t> holes) {
  return llvm::map_to_vector(holes, [&](int32_t hole) {
    return SmallVector<Value>{
        at(b, loc, cell, layout.fields[static_cast<unsigned>(hole)].front().offset)};
  });
}

// A new cell of the runtime's, which writes its header as it allocates it.
struct LowerCellNew : IdrPattern<CellNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellNewOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, runtime.allocate(rewriter, op.getLoc(),
                                            cellOf(layouts, op.getCell().getType())));
    return success();
  }
};

// A cell in the frame: a slot in the entry block of the function that holds
// it, one slot per op, allocated once per frame however often the op runs,
// so LLVM may keep it in registers when it stays in the function. Its
// header, written where the op runs, is count 1 and the cell's info with
// the stack mark (IDRIS_RT_STACK_CELL): counting works on it as on any
// cell, but when its count reaches 0 its memory is not freed, and it is
// never exclusive, so no recycle reuses it for a value that could outlive
// the frame.
struct LowerCellStack : IdrPattern<CellStackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellStackOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellOf(layouts, op.getCell().getType());
    Value slot;
    {
      OpBuilder::InsertionGuard guard(rewriter);
      Operation *scope = op->getParentWithTrait<OpTrait::AutomaticAllocationScope>();
      rewriter.setInsertionPointToStart(&scope->getRegion(0).front());
      slot = LLVM::AllocaOp::create(rewriter, loc, ptrType(getContext()),
                                    LLVM::LLVMArrayType::get(rewriter.getI8Type(), cell.size),
                                    i64Constant(rewriter, loc, 1), cellAlignment());
    }
    runtime.storeHeader(rewriter, loc, slot, cell, cell.info.onStack());
    rewriter.replaceOp(op, slot);
    return success();
  }
};

// The token's cell, or a new cell when the token is null: the take of a
// shared box gives none. An exclusive token is the cell, certainly: no
// test. The token's cell takes the header of its new constructor, unless it
// holds it already (Fields::sameConstructor).
struct LowerCellRecycle : IdrPattern<CellRecycleOp> {
  LowerCellRecycle(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                   Runtime &runtime, const Fields &fields)
      : IdrPattern(converter, ctx, layouts, runtime), fields(fields) {}

  LogicalResult matchAndRewrite(CellRecycleOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellOf(layouts, op.getCell().getType());
    Value token = adaptor.getToken().front();
    auto recycled = [&](OpBuilder &b) {
      if (!fields.sameConstructor(op))
        runtime.storeHeader(b, loc, token, cell, cell.info);
    };
    if (isExclusive(op.getToken().getType())) {
      recycled(rewriter);
      rewriter.replaceOp(op, token);
      return success();
    }
    Type ptr = token.getType();
    Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, token,
                                       nullComponent(rewriter, loc, ptr));
    auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, runtime.allocate(rewriter, loc, cell));
      rewriter.setInsertionPointToStart(choose.elseBlock());
      recycled(rewriter);
      scf::YieldOp::create(rewriter, loc, token);
    }
    rewriter.replaceOp(op, choose.getResult(0));
    return success();
  }

  const Fields &fields;
};

// The fields of the cell's constructor at their slots, zero for a hole, but
// those the cell holds already (Fields::kept); then the destination of each
// hole, the address of its word. The box is the cell.
struct LowerCellInit : IdrPattern<CellInitOp> {
  LowerCellInit(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                Runtime &runtime, const Fields &fields)
      : IdrPattern(converter, ctx, layouts, runtime), fields(fields) {}

  LogicalResult matchAndRewrite(CellInitOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellOf(layouts, op.getCell().getType());
    Value box = adaptor.getCell().front();
    std::optional<ArrayRef<bool>> kept = fields.kept(op);
    SmallVector<SmallVector<Value>> values =
        fieldsOf(rewriter, loc, cell, op.getHoles(), adaptor.getFields());
    for (auto [index, slots, field] : llvm::enumerate(cell.fields, values))
      if (!kept || !(*kept)[index])
        runtime.store(rewriter, loc, box, cellAlignment(), slots, field);
    SmallVector<SmallVector<Value>> out{{box}};
    llvm::append_range(out, destsOf(rewriter, loc, box, cell, op.getHoles()));
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }

  const Fields &fields;
};

// An unboxed constructor is its tag and its components in their slots, and
// zero in the slots it does not use: empty where the slot is counted, so
// that counting the sum counts each of its slots, as static data has it.
// A box's constructor that is still a con after idr-rc is an atom, which
// has no cell of its own (buildsCell): it is the static cell a folded atom
// constant is, so nothing is allocated that no take would free.
struct LowerCon : IdrPattern<ConOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    if (isBoxed(op.getResult().getType())) {
      MLIRContext *ctx = getContext();
      auto atom = ConAttr::get(ctx, data, tag, ArrayAttr::get(ctx, {}));
      rewriter.replaceOpWithMultiple(
          op, {runtime.constant(rewriter, loc, atom, op.getResult().getType())});
      return success();
    }
    rewriter.replaceOpWithMultiple(
        op, {unboxedSum(rewriter, loc, layouts.sum(data), tag, adaptor.getFields())});
    return success();
  }
};

// A value with no cell of its own taken apart: an unboxed sum's fields are
// its slots, which move out as they are; an atom has no field, and nothing
// is anyone's to free.
struct LowerUnpack : IdrPattern<UnpackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(UnpackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<SmallVector<Value>> fields;
    for (unsigned index = 0, n = static_cast<unsigned>(op.getFields().size()); index < n; ++index)
      fields.push_back(
          unboxedField(layouts.sum(op.getDataType()), adaptor.getValue(), op.getTag(), index));
    rewriter.replaceOpWithMultiple(op, std::move(fields));
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
    Tag tag = op.getTag();
    DataType data = op.getDataType();
    if (isBoxed(op.getValue().getType())) {
      rewriter.replaceOpWithMultiple(
          op, {runtime.load(rewriter, op.getLoc(), adaptor.getValue().front(), cellAlignment(),
                            layouts.box(data).cell(tag).fields[index])});
      return success();
    }
    rewriter.replaceOpWithMultiple(
        op, {unboxedField(layouts.sum(data), adaptor.getValue(), tag, index)});
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

// Poison may still be dropped, as what a function nobody reads is passed,
// or what idr-tail-loops forwards on the path it does not take. Poison of
// a cell pointer is the static cell `nothing` (StaticData): a cell, so
// every fact LLVM is told of a cell pointer holds of it, and static, so
// counting it changes nothing. Poison of any other idr value is poison of
// each component, but for the counted ones, which are the runtime's empty
// value: a big's word, a sum's slot, an array's cell.
struct LowerPoison : IdrPattern<ub::PoisonOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ub::PoisonOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Type type = op.getType();
    if (isCellPointer(type)) {
      rewriter.replaceOpWithMultiple(
          op, {runtime.constant(rewriter, loc, ub::PoisonAttr::get(getContext()), type)});
      return success();
    }
    SmallVector<Value> out;
    for (const layout::Component &component : layouts.components(type))
      out.push_back(component.counted
                        ? nullComponent(rewriter, loc, component.type)
                        : ub::PoisonOp::create(rewriter, loc, component.type).getResult());
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

// The patterns of cells and unboxed sums: the producers of cells and their
// init, constructors, their tags and fields, the values with no cell taken
// apart, constants, the writes of holes, and what poison and select make of
// an idr value.
void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime, const Fields &fields) {
  MLIRContext *ctx = patterns.getContext();
  patterns.add<LowerCellNew, LowerCellStack, LowerCon, LowerUnpack, LowerTag, LowerField,
               LowerConstant, LowerPoison, LowerSelect, LowerDestWrite>(converter, ctx, layouts,
                                                                        runtime);
  patterns.add<LowerCellRecycle, LowerCellInit>(converter, ctx, layouts, runtime, fields);
}

} // namespace idr::conversion
