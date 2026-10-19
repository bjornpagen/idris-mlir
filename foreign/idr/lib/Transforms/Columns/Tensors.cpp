// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of idr-columns for the ops on whole tensors and on their
// elements: an op that only moves arrays whole does to each column what it
// did to the array, a slice or a reshape keeping each column's trailing
// dimensions whole, and a read or a write at an index reads or writes each
// column there, building the record or taking it apart.

#include "idr/Transforms/Columns.h"

#include "idr/IR/Grades.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

#include <utility>

using namespace mlir;

namespace idr::columns {

namespace {

// The dimensions a column holds after the array's: its leaf's.
unsigned trailing(Type column, Type array) {
  return static_cast<unsigned>(cast<RankedTensorType>(unrestricted(column)).getRank() -
                               cast<RankedTensorType>(unrestricted(array)).getRank());
}

// Offsets, sizes and strides of a slice of an array, the same slice of a
// column: its trailing dimensions whole.
struct Mixed {
  SmallVector<OpFoldResult> offsets, sizes, strides;
};
Mixed extend(OpBuilder &b, ArrayRef<OpFoldResult> offsets, ArrayRef<OpFoldResult> sizes,
             ArrayRef<OpFoldResult> strides, RankedTensorType column, unsigned extra) {
  Mixed mixed{SmallVector<OpFoldResult>(offsets), SmallVector<OpFoldResult>(sizes),
              SmallVector<OpFoldResult>(strides)};
  for (int64_t size : column.getShape().take_back(extra)) {
    mixed.offsets.push_back(b.getIndexAttr(0));
    mixed.sizes.push_back(b.getIndexAttr(size));
    mixed.strides.push_back(b.getIndexAttr(1));
  }
  return mixed;
}

// A reassociation with each of `extra` trailing dimensions a group of its
// own, after `from` and `to` dimensions.
SmallVector<ReassociationIndices> extend(ArrayRef<ReassociationIndices> groups, unsigned to,
                                         unsigned extra) {
  SmallVector<ReassociationIndices> out(groups);
  for (unsigned i = 0; i < extra; ++i)
    out.push_back({static_cast<int64_t>(to + i)});
  return out;
}

//===----------------------------------------------------------------------===//
// Ops that move arrays whole
//===----------------------------------------------------------------------===//

// An op that does to an array of records what it does to each column: the
// op once per column, given that column of each array it takes and every
// other operand as it is, and giving that column of each array it makes.
// An empty array, a cast, a tie, a linear position entered or used, a
// choice of one of two arrays, a poison.
struct PerColumn : ConversionPattern {
  PerColumn(const TypeConverter &converter, StringRef name, MLIRContext *ctx)
      : ConversionPattern(converter, name, 1, ctx) {}
  LogicalResult matchAndRewrite(Operation *op, ArrayRef<ValueRange> operands,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(*getTypeConverter(), op->getResultTypes(), results, counts)))
      return failure();
    unsigned columns = 1;
    auto widen = [&](size_t count) {
      if (count == 1)
        return true;
      if (columns == 1)
        columns = static_cast<unsigned>(count);
      return count == columns;
    };
    if (!llvm::all_of(operands, [&](ValueRange range) { return widen(range.size()); }) ||
        !llvm::all_of(counts, [&](unsigned count) { return widen(count) && count == columns; }))
      return failure();
    SmallVector<SmallVector<Value>> replaced(op->getNumResults());
    ArrayRef<Type> types = results;
    // The ops it takes have no region, so each column's op is the op made
    // again on that column.
    for (unsigned j = 0; j < columns; ++j) {
      SmallVector<Value> columnOperands = llvm::map_to_vector(
          operands, [&](ValueRange range) { return range.size() == 1 ? range.front() : range[j]; });
      SmallVector<Type> columnTypes;
      for (unsigned r = 0, e = op->getNumResults(); r < e; ++r)
        columnTypes.push_back(types[r * columns + j]);
      Operation *made = remakeOp(rewriter, op, columnOperands, columnTypes);
      for (unsigned r = 0, e = op->getNumResults(); r < e; ++r)
        replaced[r].push_back(made->getResult(r));
    }
    rewriter.replaceOpWithMultiple(op, replaced);
    return success();
  }
};

struct DimColumns : OpConversionPattern<tensor::DimOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::DimOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    // Every column has the array's dimensions first.
    rewriter.replaceOpWithNewOp<tensor::DimOp>(op, adaptor.getSource().front(),
                                               adaptor.getIndex().front());
    return success();
  }
};

struct ExtractSliceColumns : OpConversionPattern<tensor::ExtractSliceOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::ExtractSliceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    if (failed(getTypeConverter()->convertType(op.getType(), results)))
      return failure();
    SmallVector<Value> made;
    for (auto [column, type] : llvm::zip_equal(adaptor.getSource(), results)) {
      auto to = cast<RankedTensorType>(type);
      Mixed mixed = extend(rewriter, op.getMixedOffsets(), op.getMixedSizes(),
                           op.getMixedStrides(), cast<RankedTensorType>(column.getType()),
                           trailing(column.getType(), op.getSourceType()));
      made.push_back(tensor::ExtractSliceOp::create(rewriter, op.getLoc(), to, column,
                                                    mixed.offsets, mixed.sizes, mixed.strides));
    }
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

struct InsertSliceColumns : OpConversionPattern<tensor::InsertSliceOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::InsertSliceOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (adaptor.getSource().size() != adaptor.getDest().size())
      return failure();
    SmallVector<Value> made;
    for (auto [column, into] : llvm::zip_equal(adaptor.getSource(), adaptor.getDest())) {
      Mixed mixed = extend(rewriter, op.getMixedOffsets(), op.getMixedSizes(),
                           op.getMixedStrides(), cast<RankedTensorType>(into.getType()),
                           trailing(into.getType(), op.getDestType()));
      made.push_back(tensor::InsertSliceOp::create(rewriter, op.getLoc(), column, into,
                                                   mixed.offsets, mixed.sizes, mixed.strides));
    }
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

struct CollapseColumns : OpConversionPattern<tensor::CollapseShapeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::CollapseShapeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    if (failed(getTypeConverter()->convertType(op.getType(), results)))
      return failure();
    SmallVector<Value> made;
    for (auto [column, type] : llvm::zip_equal(adaptor.getSrc(), results)) {
      unsigned extra = trailing(column.getType(), op.getSrcType());
      made.push_back(tensor::CollapseShapeOp::create(
          rewriter, op.getLoc(), type, column,
          extend(op.getReassociationIndices(), static_cast<unsigned>(op.getSrcType().getRank()),
                 extra)));
    }
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

struct ExpandColumns : OpConversionPattern<tensor::ExpandShapeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::ExpandShapeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    if (failed(getTypeConverter()->convertType(op.getType(), results)))
      return failure();
    SmallVector<Value> made;
    for (auto [column, type] : llvm::zip_equal(adaptor.getSrc(), results)) {
      auto to = cast<RankedTensorType>(type);
      unsigned extra = trailing(column.getType(), op.getSrcType());
      SmallVector<OpFoldResult> shape = op.getMixedOutputShape();
      for (int64_t size : to.getShape().take_back(extra))
        shape.push_back(rewriter.getIndexAttr(size));
      made.push_back(tensor::ExpandShapeOp::create(
          rewriter, op.getLoc(), to, column,
          extend(op.getReassociationIndices(), static_cast<unsigned>(op.getResultType().getRank()),
                 extra),
          shape));
    }
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

//===----------------------------------------------------------------------===//
// Reads and writes at an index
//===----------------------------------------------------------------------===//

struct ExtractColumns : OpConversionPattern<tensor::ExtractOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::ExtractOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const Records &records = recordsOf(*getTypeConverter());
    std::optional<Record> element = records.recordOf(op.getType());
    if (!element)
      return rewriter.notifyMatchFailure(op, "reads no record");
    rewriter.replaceOp(op, records.readRecord(rewriter, op.getLoc(), *element,
                                              adaptor.getTensor(), flatten(adaptor.getIndices())));
    return success();
  }
};

struct InsertColumns : OpConversionPattern<tensor::InsertOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(tensor::InsertOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const Records &records = recordsOf(*getTypeConverter());
    std::optional<Record> element = records.recordOf(op.getScalar().getType());
    if (!element)
      return rewriter.notifyMatchFailure(op, "writes no record");
    SmallVector<Value> made = records.writeRecord(rewriter, op.getLoc(),
                                                  adaptor.getScalar().front(), *element,
                                                  adaptor.getDest(), flatten(adaptor.getIndices()));
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

} // namespace

// Every op here is legal once the types it carries are converted, but a
// select: a choice by a condition per element is no choice of whole arrays,
// and stays as it is.
void populateTensorColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                                  ConversionTarget &target) {
  MLIRContext *ctx = patterns.getContext();
  ConversionTarget::DynamicLegalityCallbackFn legal = whole(converter);
  addColumns<DimColumns, tensor::DimOp>(converter, patterns, target, legal);
  addColumns<ExtractSliceColumns, tensor::ExtractSliceOp>(converter, patterns, target, legal);
  addColumns<InsertSliceColumns, tensor::InsertSliceOp>(converter, patterns, target, legal);
  addColumns<CollapseColumns, tensor::CollapseShapeOp>(converter, patterns, target, legal);
  addColumns<ExpandColumns, tensor::ExpandShapeOp>(converter, patterns, target, legal);
  addColumns<ExtractColumns, tensor::ExtractOp>(converter, patterns, target, legal);
  addColumns<InsertColumns, tensor::InsertOp>(converter, patterns, target, legal);
  ConversionTarget::DynamicLegalityCallbackFn select =
      [&converter](Operation *op) -> std::optional<bool> {
    return isa<ShapedType>(cast<arith::SelectOp>(op).getCondition().getType()) ||
           converter.isLegal(op);
  };
  std::pair<StringRef, ConversionTarget::DynamicLegalityCallbackFn> perColumn[] = {
      {tensor::EmptyOp::getOperationName(), legal}, {tensor::CastOp::getOperationName(), legal},
      {TieShapeOp::getOperationName(), legal},      {LinEnterOp::getOperationName(), legal},
      {LinUseOp::getOperationName(), legal},        {arith::SelectOp::getOperationName(), select},
      {ub::PoisonOp::getOperationName(), legal}};
  for (auto &[name, legality] : perColumn) {
    patterns.add<PerColumn>(converter, name, ctx);
    target.addDynamicallyLegalOp(OperationName(name, ctx), legality);
  }
}

} // namespace idr::columns
