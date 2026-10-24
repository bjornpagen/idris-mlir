// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of cells and of data values: a counted cell's source and its
// reuse, each of which writes the cell's header, and its init, which writes
// its fields and gives each hole's destination; the constructors that build
// no cell; the reads of tags and fields, each by the layout its type is (a
// cell, or words in place), a field re-packed between the type its slot is
// laid out at and its type at its value's application. A cell of a lexical
// lifetime is Lifetimes.cpp's, a write through a destination
// Destinations.cpp's, and a value of ours that is no cell Values.cpp's.
// The lifetime an op here states of a value it makes is read by no
// pattern: a value at run time is its words, and an arena's handle is read
// by the source of the cell put into it.
//
// A frame of a frame stack is laid out as a cell and lives on its thread's
// stack of frames, contiguous in chunks the runtime holds: a push
// (data.con) takes the next frame's bytes and writes it, uncounted; the
// resume's match reads its tag; and taking it apart (count.unpack) reads
// its values out and gives its bytes back, the runtime returning a chunk
// it no longer needs and keeping one spare. Its memory is the next push's,
// so nothing read of it stays. It holds no lifetime: a cursor inside a
// function is a slot of that function's frame, gone at the jump, so the
// lifetimes of the functions on a cycle's stack go in as their parameters
// and come back out as their results.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A data value's type, which an op reads its layout from.
DataType dataOf(Type type) { return cast<DataType>(unrestricted(type)); }

// The components each field of a constructor stores in a cell laid out as
// `cell`, its slots at the types `slots`: each of `operands`, given as
// `given`, re-packed from its own type into its slot's, in field order, and
// zero for each of `holes`, so that the cell is whole until the hole's
// destination is written, an object slot holding an empty reference.
SmallVector<SmallVector<Value>> fieldsOf(OpBuilder &b, Location loc, const Layouts &layouts,
                                         Runtime &runtime, const layout::Cell &cell,
                                         ArrayRef<Type> slots, ArrayRef<int32_t> holes,
                                         ValueRange operands, ArrayRef<ValueRange> given) {
  SmallVector<SmallVector<Value>> fields;
  unsigned next = 0;
  for (auto [index, slotsOf] : llvm::enumerate(cell.fields)) {
    if (!llvm::binary_search(holes, static_cast<int32_t>(index))) {
      Type type = operands[next].getType();
      fields.push_back(
          repack(b, loc, layouts, runtime, type, slots[index], given[next], takesOf(type)));
      ++next;
      continue;
    }
    fields.push_back(llvm::map_to_vector(slotsOf, [&](const layout::Slot &slot) -> Value {
      return LLVM::ZeroOp::create(b, loc, slot.type);
    }));
  }
  return fields;
}

// A new counted cell of the runtime's, which writes its header as it
// allocates it.
struct LowerCellNew : IdrPattern<CellNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellNewOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, runtime.allocate(rewriter, op.getLoc(),
                                            cellLayoutOf(layouts, op.getCell().getType())));
    return success();
  }
};

// The token's cell made the cell of the new constructor. A token that
// holds its cell, as its grade says, is the cell, with no test; its header
// is kept where the token's one source is the constructor the cell is for,
// read off the two types, and written otherwise, its count the 1 its take
// left. A token that may be null is the copy budget's fallback, the shared
// path of a match on uniqueness that gave `token.null`: the one test of it
// left to run, which a fresh cell answers. The memory held another cell,
// so loads through the result see only what is written through it.
struct LowerCellRecycle : IdrPattern<CellRecycleOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellRecycleOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto cellType = cast<CellType>(op.getCell().getType());
    const layout::Cell &cell = cellLayoutOf(layouts, cellType);
    auto token = cast<ReuseTokenType>(unrestricted(op.getToken().getType()));
    Value held = adaptor.getToken().front();
    auto recycled = [&](OpBuilder &b) {
      if (token.getSources() != ArrayRef<Type>{cellType.getValue()})
        runtime.storeInfoAndWords(b, loc, held, cell);
    };
    if (claims(op.getToken().getType(), Unique::Deep)) {
      recycled(rewriter);
      rewriter.replaceOp(op, runtime.launder(rewriter, loc, held));
      return success();
    }
    Type ptr = held.getType();
    Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, held,
                                       nullComponent(rewriter, loc, ptr));
    auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
    {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      scf::YieldOp::create(rewriter, loc, runtime.allocate(rewriter, loc, cell));
      rewriter.setInsertionPointToStart(choose.elseBlock());
      recycled(rewriter);
      scf::YieldOp::create(rewriter, loc, held);
    }
    rewriter.replaceOp(op, runtime.launder(rewriter, loc, choose.getResult(0)));
    return success();
  }
};

// The fields of the cell's constructor at their slots, zero for a hole;
// then the destination of each hole, the address of each of its slots. The
// value is the cell.
struct LowerCellInit : IdrPattern<CellInitOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellInitOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto cellType = cast<CellType>(op.getCell().getType());
    const layout::Cell &cell = cellLayoutOf(layouts, cellType);
    Value value = adaptor.getCell().front();
    ArrayRef<int32_t> holes = op.getHoles();
    SmallVector<SmallVector<Value>> fields =
        fieldsOf(rewriter, loc, layouts, runtime, cell,
                 layouts.fieldTypes(cellType.getData(), cellType.getTag()), holes, op.getFields(),
                 adaptor.getFields());
    for (auto [slots, field] : llvm::zip_equal(cell.fields, fields))
      runtime.store(rewriter, loc, value, cellAlignment(), slots, field);
    SmallVector<SmallVector<Value>> out{{value}};
    for (int32_t hole : holes)
      out.push_back(llvm::map_to_vector(
          cell.fields[static_cast<unsigned>(hole)],
          [&](const layout::Slot &slot) { return at(rewriter, loc, value, slot.offset); }));
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

// A constructor that builds no cell: a value in place, its tag and its
// components in their words, zero in the words it does not use (empty
// where the word is counted, so that counting the value counts each of its
// words, as static data has it); or an atom of a family laid out in a cell,
// which has no cell of its own and is the static cell of its constructor,
// so nothing is allocated that no count would free.
struct LowerDataCon : IdrPattern<DataConOp> {
  using IdrPattern::IdrPattern;
  // Its fields, each re-packed into the type its slot is laid out at.
  SmallVector<SmallVector<Value>> slotted(OpBuilder &b, DataConOp op,
                                          OneToNOpAdaptor adaptor) const {
    return intoSlots(b, op.getLoc(), layouts, runtime, op.getDataType(), op.getTag(),
                     op.getFields(), adaptor.getFields());
  }
  LogicalResult matchAndRewrite(DataConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    switch (data.layout()) {
    case Layout::InPlace: {
      SmallVector<SmallVector<Value>> fields = slotted(rewriter, op, adaptor);
      SmallVector<ValueRange> given(fields.begin(), fields.end());
      rewriter.replaceOpWithMultiple(op,
                                     {unboxedSum(rewriter, loc, layouts.sum(data), tag, given)});
      return success();
    }
    case Layout::FrameStack: {
      const layout::Cell &frame = layouts.cells(data).cell(tag);
      Value address = runtime
                          .call(rewriter, loc, idr::runtime::helper::framePush,
                                i64Constant(rewriter, loc, frame.size))
                          .getResult();
      runtime.storeUncountedHeader(rewriter, loc, address, frame);
      for (auto [slots, field] : llvm::zip_equal(frame.fields, slotted(rewriter, op, adaptor)))
        runtime.store(rewriter, loc, address, cellAlignment(), slots, field);
      rewriter.replaceOp(op, address);
      return success();
    }
    case Layout::Cell: {
      if (!op.getFields().empty())
        return rewriter.notifyMatchFailure(op, "a constructor of a cell with fields is counting's");
      MLIRContext *ctx = getContext();
      auto atom = ConAttr::get(ctx, data.refinedTo(tag, {}), ArrayAttr::get(ctx, {}));
      rewriter.replaceOpWithMultiple(op, {constantComponents(rewriter, loc, layouts,
                                                             runtime.statics(), atom,
                                                             op.getResult().getType())});
      return success();
    }
    default:
      return rewriter.notifyMatchFailure(op, "a numeral is built by its conversions");
    }
  }
};

// A value in place taken apart: its fields are its words, which move out as
// they are, each re-packed from its slot's type into the type it is taken
// at. A frame popped: its values read out, then its bytes given back.
struct LowerUnpack : IdrPattern<CountUnpackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountUnpackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    SmallVector<SmallVector<Value>> slots;
    if (data.layout() == Layout::FrameStack) {
      for (ArrayRef<layout::Slot> each : layouts.cells(data).cell(tag).fields)
        slots.push_back(
            runtime.load(rewriter, loc, adaptor.getValue().front(), cellAlignment(), each));
    } else {
      for (unsigned index = 0, n = static_cast<unsigned>(op.getFields().size()); index < n; ++index)
        slots.push_back(unboxedField(layouts.sum(data), adaptor.getValue(), tag, index));
    }
    SmallVector<SmallVector<Value>> fields;
    for (auto [field, slot, read] :
         llvm::zip_equal(op.getFields(), layouts.fieldTypes(data, tag), slots))
      fields.push_back(repack(rewriter, loc, layouts, runtime, slot, field.getType(), read,
                              takesOf(field.getType())));
    if (data.layout() == Layout::FrameStack)
      runtime.call(rewriter, loc, idr::runtime::helper::framePop, adaptor.getValue().front());
    rewriter.replaceOpWithMultiple(op, std::move(fields));
    return success();
  }
};

// The tag, by the layout: a cell's is in its header, and its group's word
// where its sum has one; a value in place holds it in its tag word, or has
// one constructor and tag 0.
struct LowerDataTag : IdrPattern<DataTagOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DataTagOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = dataOf(op.getValue().getType());
    switch (data.layout()) {
    case Layout::Cell:
    case Layout::FrameStack:
      rewriter.replaceOp(op, runtime.loadTag(rewriter, loc, adaptor.getValue().front(), data,
                                             contentsOf(data)));
      return success();
    case Layout::InPlace: {
      const layout::SumLayout &layout = layouts.sum(data);
      if (!layout.tag)
        rewriter.replaceOpWithNewOp<arith::ConstantIntOp>(
            op, static_cast<int64_t>(static_cast<uint32_t>(tagOf(data))), 64);
      else
        rewriter.replaceOpWithNewOp<arith::ExtUIOp>(op, rewriter.getI64Type(),
                                                    adaptor.getValue().front());
      return success();
    }
    default:
      return rewriter.notifyMatchFailure(op, "a numeral is read by its conversions");
    }
  }
};

// A field's components, loaded from a cell's slots, or read from a value's
// words in place, then re-packed from the type its slot is laid out at
// into the field's type at the value's application, read where the value
// keeps it.
struct LowerDataField : IdrPattern<DataFieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DataFieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto index = static_cast<unsigned>(op.getIndex());
    Tag tag = op.getTag();
    DataType data = op.getDataType();
    SmallVector<Value> slot;
    switch (data.layout()) {
    case Layout::Cell:
    case Layout::FrameStack:
      slot = runtime.load(rewriter, loc, adaptor.getValue().front(), cellAlignment(),
                          layouts.cells(data).cell(tag).fields[index], contentsOf(data));
      break;
    case Layout::InPlace:
      slot = unboxedField(layouts.sum(data), adaptor.getValue(), tag, index);
      break;
    default:
      return rewriter.notifyMatchFailure(op, "a numeral is read by its conversions");
    }
    rewriter.replaceOpWithMultiple(
        op, {repack(rewriter, loc, layouts, runtime, layouts.fieldTypes(data, tag)[index],
                    op.getResult().getType(), slot, readInPlace)});
    return success();
  }
};

} // namespace

// The patterns of cells and data values: a counted cell's source, reuse and
// init, constructors, their tags and fields, and a value in place taken
// apart.
void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCellNew, LowerCellRecycle, LowerCellInit, LowerDataCon, LowerUnpack,
               LowerDataTag, LowerDataField>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
