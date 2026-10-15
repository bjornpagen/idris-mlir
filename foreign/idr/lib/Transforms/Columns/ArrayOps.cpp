// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of idr-columns for the array ops: each array of records an
// op makes, folds or transposes is its columns, an accumulator that is a
// record is its leaves in the op's region, and the region yields the
// leaves of each record it gives.

#include "idr/Transforms/Columns.h"

using namespace mlir;

namespace idr::columns {

namespace {

struct TransposeColumns : OpConversionPattern<TransposeOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(TransposeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    if (failed(getTypeConverter()->convertType(op.getType(), results)))
      return failure();
    SmallVector<Value> made;
    for (auto [column, type] : llvm::zip_equal(adaptor.getInput(), results)) {
      SmallVector<int64_t> permutation(op.getPermutation());
      auto rank = static_cast<int64_t>(permutation.size());
      for (int64_t d = rank, e = cast<RankedTensorType>(type).getRank(); d < e; ++d)
        permutation.push_back(d);
      made.push_back(TransposeOp::create(rewriter, op.getLoc(), type, column, permutation));
    }
    rewriter.replaceOpWithMultiple(op, {made});
    return success();
  }
};

//===----------------------------------------------------------------------===//
// The array ops
//===----------------------------------------------------------------------===//

// A tabulation makes each array of records as its columns, its region
// yielding the leaves of each record (ArrayYieldColumns).
template <typename OpT>
struct TabulateColumns : OpConversionPattern<OpT> {
  using OpConversionPattern<OpT>::OpConversionPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(*this->getTypeConverter(), op->getResultTypes(), results, counts)))
      return failure();
    Operation *made = remake(rewriter, op, flatten(adaptor.getOperands()), results);
    SmallVector<SmallVector<Value>> replaced = runs(made->getResults(), counts);
    rewriter.replaceOpWithMultiple(op, replaced);
    return success();
  }
};

// A fold or a scan over arrays of records folds their columns: each
// accumulator that is a record is its leaves in the region, and one that
// is a cell of records its columns, built again where an op of the region
// that the conversion does not take reads it.
template <typename OpT>
struct FoldColumns : OpConversionPattern<OpT> {
  using OpConversionPattern<OpT>::OpConversionPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpConversionPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const TypeConverter &converter = *this->getTypeConverter();
    SmallVector<Type> results;
    SmallVector<unsigned> counts;
    if (failed(convertEach(converter, op->getResultTypes(), results, counts)))
      return failure();
    Block *body = op.getBody();
    TypeConverter::SignatureConversion signature(body->getNumArguments());
    for (BlockArgument arg : body->getArguments()) {
      SmallVector<Type> types;
      if (recordOf(arg.getType()))
        leavesOf(arg.getType(), types);
      else if (failed(converter.convertType(arg.getType(), types)))
        return failure();
      signature.addInputs(arg.getArgNumber(), types);
    }
    Operation *made = remake(rewriter, op, flatten(adaptor.getOperands()), results);
    rewriter.applySignatureConversion(&made->getRegion(0).front(), signature, &converter);
    SmallVector<SmallVector<Value>> replaced = runs(made->getResults(), counts);
    rewriter.replaceOpWithMultiple(op, replaced);
    return success();
  }
};

// What a region of the generating set yields: each record taken apart into
// its leaves, each cell of records its columns. An update's region yields
// into an array a world orders, which holds its records whole.
struct ArrayYieldColumns : OpConversionPattern<ArrayYieldOp> {
  using OpConversionPattern::OpConversionPattern;
  LogicalResult matchAndRewrite(ArrayYieldOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> operands;
    for (auto [value, columns] : llvm::zip_equal(op.getValues(), adaptor.getValues())) {
      if (std::optional<Record> record = recordOf(value.getType()))
        llvm::append_range(operands, takeApart(rewriter, op.getLoc(), columns.front(), *record));
      else
        llvm::append_range(operands, columns);
    }
    rewriter.modifyOpInPlace(op, [&] { op->setOperands(operands); });
    return success();
  }
};

} // namespace

void populateArrayColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns) {
  patterns.add<TransposeColumns, TabulateColumns<TabulateOp>, TabulateColumns<TabulateIOOp>,
               FoldColumns<FoldLastOp>, FoldColumns<ScanLastOp>, ArrayYieldColumns>(
      converter, patterns.getContext());
}

} // namespace idr::columns
