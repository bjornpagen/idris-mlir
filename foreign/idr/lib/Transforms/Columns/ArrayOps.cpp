// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of idr-columns for the generating set: each array of
// records an op writes is its columns, destinations and results together,
// an accumulator that is a record is its leaves in the op's region, and
// the region yields the leaves of each record it gives.

#include "idr/Transforms/Columns.h"

using namespace mlir;

namespace idr::columns {

namespace {

// A fold or a scan over arrays of records folds their columns: each
// accumulator that is a record is its leaves in the region, and one that
// is a cell of records its columns, built again where an op of the region
// that the conversion does not take reads it. An op whose operands are
// groups (AttrSizedOperandSegments, as a scan's inputs and destinations
// are) keeps their sizes in its properties, which the op made again
// carries over: each group is then as many as its columns.
template <typename OpT>
struct FoldColumns : OpConversionPattern<OpT> {
  using OpConversionPattern<OpT>::OpConversionPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const TypeConverter &converter = *this->getTypeConverter();
    const Records &records = recordsOf(converter);
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(converter, op->getResultTypes(), results, counts)))
      return failure();
    Block *body = op.getBody();
    TypeConverter::SignatureConversion signature(body->getNumArguments());
    for (BlockArgument arg : body->getArguments()) {
      SmallVector<Type> types;
      if (records.recordOf(arg.getType()))
        records.leavesOf(arg.getType(), types);
      else if (failed(converter.convertType(arg.getType(), types)))
        return failure();
      signature.addInputs(arg.getArgNumber(), types);
    }
    Operation *made = remakeOp(rewriter, op, flatten(adaptor.getOperands()), results);
    if constexpr (OpT::template hasTrait<OpTrait::AttrSizedOperandSegments>()) {
      auto &sizes = cast<OpT>(made).getProperties().operandSegmentSizes;
      for (unsigned group = 0; group < sizes.size(); ++group)
        sizes[group] = static_cast<int32_t>(flatten(adaptor.getODSOperands(group)).size());
    }
    rewriter.applySignatureConversion(&made->getRegion(0).front(), signature, &converter);
    SmallVector<SmallVector<Value>> replaced = runs(made->getResults(), counts);
    rewriter.replaceOpWithMultiple(op, replaced);
    return success();
  }
};

// What a region of the generating set yields: each record taken apart into
// its leaves, each cell of records its columns.
struct ArrayYieldColumns : OpConversionPattern<ArrayYieldOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(ArrayYieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const Records &records = recordsOf(*getTypeConverter());
    SmallVector<Value> operands;
    for (auto [value, columns] : llvm::zip_equal(op.getValues(), adaptor.getValues())) {
      if (std::optional<Record> record = records.recordOf(value.getType()))
        llvm::append_range(operands,
                           records.takeApart(rewriter, op.getLoc(), columns.front(), *record));
      else
        llvm::append_range(operands, columns);
    }
    rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
    return success();
  }
};

} // namespace

// A tabulation writes each array of records as its columns, its region
// yielding the leaves of each record (ResultColumns, ArrayYieldColumns). A
// fold or a scan is legal once its region's accumulators are converted
// too, and a yield once it yields no record.
void populateArrayColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                                 ConversionTarget &target) {
  ConversionTarget::DynamicLegalityCallbackFn legal = whole(converter);
  ConversionTarget::DynamicLegalityCallbackFn folded =
      [&converter](Operation *op) -> std::optional<bool> {
    return converter.isLegal(op) && converter.isLegal(&op->getRegion(0));
  };
  addColumns<ResultColumns<ArrayTabulateOp>, ArrayTabulateOp>(converter, patterns, target, legal);
  addColumns<FoldColumns<ArrayFoldLastOp>, ArrayFoldLastOp>(converter, patterns, target, folded);
  addColumns<FoldColumns<ArrayScanLastOp>, ArrayScanLastOp>(converter, patterns, target, folded);
  addColumns<ArrayYieldColumns, ArrayYieldOp>(
      converter, patterns, target, [&converter](Operation *op) -> std::optional<bool> {
        return converter.isLegal(op) &&
               llvm::none_of(cast<ArrayYieldOp>(op).getValues().getTypes(),
                             [&converter](Type type) {
                               return recordsOf(converter).recordOf(type).has_value();
                             });
      });
}

} // namespace idr::columns
