// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of cells and of data values: a counted cell's source and its
// reuse, each of which writes the cell's header, and its init, which writes
// its fields; the constructors that build no cell; the reads of tags and
// fields, each by the layout its type is (a cell, or words in place); and
// what poison and select make of a value of ours. A cell of a lexical
// lifetime is Lifetimes.cpp's.
//
// A frame of a frame stack is laid out as a cell and lives on its thread's
// stack of frames, contiguous in chunks the runtime holds: a push
// (data.con) takes the next frame's bytes and writes it, uncounted; the
// resume's match reads its tag; and taking it apart (count.unpack) reads
// its values out and gives its bytes back, the runtime returning a chunk
// it no longer needs and keeping one spare. Its memory is the next push's,
// so nothing read of it stays.

#include "Lower/Lower.h"

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
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A data value's type, which an op reads its layout from.
DataType dataOf(Type type) { return cast<DataType>(unrestricted(type)); }

// What a load of a cell of `data` reads: a data cell is immutable until its
// memory is reused, which launders the pointer; a memo cell's state and
// fields change when it is forced, and a frame's memory is the next push's.
Contents contentsOf(DataType data) {
  return data.memo() || data.layout() == Layout::FrameStack ? Contents::MayChange
                                                             : Contents::Stays;
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
    auto token = cast<TokenType>(unrestricted(op.getToken().getType()));
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
// then the destination of each hole, the address of its word. The value is
// the cell.
struct LowerCellInit : IdrPattern<CellInitOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CellInitOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    const layout::Cell &cell = cellLayoutOf(layouts, op.getCell().getType());
    Value value = adaptor.getCell().front();
    ArrayRef<int32_t> holes = op.getHoles();
    SmallVector<SmallVector<Value>> fields = fieldsOf(rewriter, loc, cell, holes, adaptor.getFields());
    for (auto [slots, field] : llvm::zip_equal(cell.fields, fields))
      runtime.store(rewriter, loc, value, cellAlignment(), slots, field);
    SmallVector<SmallVector<Value>> out{{value}};
    for (int32_t hole : holes)
      out.push_back({at(rewriter, loc, value,
                        cell.fields[static_cast<unsigned>(hole)].front().offset)});
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
  LogicalResult matchAndRewrite(DataConOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    switch (data.layout()) {
    case Layout::InPlace:
      rewriter.replaceOpWithMultiple(
          op, {unboxedSum(rewriter, loc, layouts.sum(data), tag, adaptor.getFields())});
      return success();
    case Layout::FrameStack: {
      const layout::Cell &frame = layouts.cells(data).cell(tag);
      Value address = runtime
                          .call(rewriter, loc, idr::runtime::helper::framePush,
                                i64Constant(rewriter, loc, frame.size))
                          .getResult();
      runtime.storeUncountedHeader(rewriter, loc, address, frame);
      for (auto [slots, field] : llvm::zip_equal(frame.fields, adaptor.getFields()))
        runtime.store(rewriter, loc, address, cellAlignment(), slots, field);
      rewriter.replaceOp(op, address);
      return success();
    }
    case Layout::Cell: {
      if (!op.getFields().empty())
        return rewriter.notifyMatchFailure(op, "a constructor of a cell with fields is counting's");
      MLIRContext *ctx = getContext();
      auto atom = ConAttr::get(ctx, dataOf(op.getResult().getType()), ArrayAttr::get(ctx, {}));
      rewriter.replaceOpWithMultiple(
          op, {runtime.constant(rewriter, loc, atom, op.getResult().getType())});
      return success();
    }
    default:
      return rewriter.notifyMatchFailure(op, "a numeral is built by its conversions");
    }
  }
};

// A value in place taken apart: its fields are its words, which move out as
// they are.
struct LowerUnpack : IdrPattern<CountUnpackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountUnpackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    DataType data = op.getDataType();
    // A frame popped: its values read out, then its bytes given back.
    if (data.layout() == Layout::FrameStack) {
      Location loc = op.getLoc();
      Value frame = adaptor.getValue().front();
      SmallVector<SmallVector<Value>> fields = llvm::map_to_vector(
          layouts.cells(data).cell(op.getTag()).fields, [&](ArrayRef<layout::Slot> slots) {
            return runtime.load(rewriter, loc, frame, cellAlignment(), slots);
          });
      runtime.call(rewriter, loc, idr::runtime::helper::framePop, frame);
      rewriter.replaceOpWithMultiple(op, std::move(fields));
      return success();
    }
    SmallVector<SmallVector<Value>> fields;
    for (unsigned index = 0, n = static_cast<unsigned>(op.getFields().size()); index < n; ++index)
      fields.push_back(
          unboxedField(layouts.sum(op.getDataType()), adaptor.getValue(), op.getTag(), index));
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
// words in place.
struct LowerDataField : IdrPattern<DataFieldOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DataFieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    auto index = static_cast<unsigned>(op.getIndex());
    Tag tag = op.getTag();
    DataType data = op.getDataType();
    switch (data.layout()) {
    case Layout::Cell:
    case Layout::FrameStack:
      rewriter.replaceOpWithMultiple(
          op, {runtime.load(rewriter, op.getLoc(), adaptor.getValue().front(), cellAlignment(),
                            layouts.cells(data).cell(tag).fields[index], contentsOf(data))});
      return success();
    case Layout::InPlace:
      rewriter.replaceOpWithMultiple(
          op, {unboxedField(layouts.sum(data), adaptor.getValue(), tag, index)});
      return success();
    default:
      return rewriter.notifyMatchFailure(op, "a numeral is read by its conversions");
    }
  }
};

// The same value at a type its refinements make equal to its own: the same
// words where the two layouts are; where an index known inside the function
// changes the layout, the re-pack is the layout's, which this does not make.
struct LowerReindex : IdrPattern<DataReindexOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DataReindexOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> converted;
    if (failed(getTypeConverter()->convertType(op.getResult().getType(), converted)))
      return rewriter.notifyMatchFailure(op, "the result's type does not convert");
    ValueRange value = adaptor.getValue();
    if (!llvm::equal(converted, value.getTypes()))
      return rewriter.notifyMatchFailure(op, "a reindex that changes the layout");
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(value)});
    return success();
  }
};

// The region in which an erased equality holds runs once, in place: the
// values forwarded into it are its arguments, its yield the op's results.
struct LowerAssume : IdrPattern<IndexAssumeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(IndexAssumeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    FailureOr<SmallVector<SmallVector<Type>>> converted =
        convertedResults(op, *getTypeConverter());
    if (failed(converted))
      return rewriter.notifyMatchFailure(op, "a result's type does not convert");
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : *converted)
      llvm::append_range(flat, components);
    auto run = scf::ExecuteRegionOp::create(rewriter, op.getLoc(), flat);
    SmallVector<SmallVector<Value>> args = llvm::map_to_vector(
        adaptor.getForwarded(), [](ValueRange forwarded) { return SmallVector<Value>(forwarded); });
    moveRegion(rewriter, *getTypeConverter(), op.getBody(), args, run.getRegion());
    rewriter.replaceOpWithMultiple(op, groupResults(run.getResults(), *converted));
    return success();
  }
};

// Strings, bigs and cells, memo cells among them, are static data; a
// constant in place is its components.
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
// or what a loop forwards on the path it does not take. Poison of a cell
// pointer is the static cell `nothing`: a cell, so every fact LLVM is told
// of a cell pointer holds of it, and static, so counting it changes
// nothing. Poison of any other value of ours is poison of each component,
// but for the counted ones, which are the runtime's empty value: a big's
// word, a sum's slot, an array's cell.
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
      out.push_back(component.counted()
                        ? nullComponent(rewriter, loc, component.type)
                        : ub::PoisonOp::create(rewriter, loc, component.type).getResult());
    rewriter.replaceOpWithMultiple(op, {out});
    return success();
  }
};

// A select of a value of ours selects each of its components.
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

// The patterns of cells and data values: a counted cell's source, reuse and
// init, constructors, their tags and fields, a value in place taken apart,
// a reindex and an assumed equality, constants, the writes of holes, and
// what poison and select make of a value of ours.
void populateCellPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCellNew, LowerCellRecycle, LowerCellInit, LowerDataCon, LowerUnpack,
               LowerDataTag, LowerDataField, LowerReindex, LowerAssume, LowerConstant,
               LowerPoison, LowerSelect, LowerDestWrite>(converter, patterns.getContext(), layouts,
                                                         runtime);
}

} // namespace idr::conversion
