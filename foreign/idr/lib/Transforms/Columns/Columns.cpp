// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-columns: every array of records of the program held as its columns,
// in one partial conversion of the program. The conversion is total on the
// program: every op it takes has its pattern, and every op it does not
// take keeps the array whole, gathered and taken apart where it meets it.
// A pattern that fails would be this pass's own error, never the
// program's.

#include "idr/Transforms/Columns.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

namespace idr {
#define GEN_PASS_DEF_IDRCOLUMNS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::columns {

void populateColumnPatterns(const TypeConverter &converter, RewritePatternSet &patterns,
                            ConversionTarget &target) {
  populateCallColumnPatterns(converter, patterns);
  populateTensorColumnPatterns(converter, patterns);
  populateArrayColumnPatterns(converter, patterns);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, patterns, target);

  // Every other op holds an array of records whole: the conversion leaves
  // it, gathering the array it is given and taking apart the one it gives.
  // A match's regions bind the fields of its constructors, which a data
  // type holds whole, so only what a match gives is converted; a fold's
  // and a scan's regions bind their accumulators, which are converted.
  target.markUnknownOpDynamicallyLegal([](Operation *) { return true; });
  auto whole = [&converter](Operation *op) { return converter.isLegal(op); };
  target.addDynamicallyLegalOp<FuncOp>([&converter](FuncOp fn) {
    return converter.isSignatureLegal(fn.getFunctionType()) && converter.isLegal(&fn.getBody());
  });
  target.addDynamicallyLegalOp<CallOp, ReturnOp, YieldOp, MatchOp, MatchLitOp, TabulateOp,
                               TabulateIOOp, TransposeOp, TieShapeOp, LinEnterOp, LinUseOp>(whole);
  target.addDynamicallyLegalOp<FoldLastOp, ScanLastOp>([&converter](Operation *op) {
    return converter.isLegal(op) && converter.isLegal(&op->getRegion(0));
  });
  target.addDynamicallyLegalOp<tensor::EmptyOp, tensor::CastOp, tensor::DimOp, tensor::ExtractOp,
                               tensor::InsertOp, tensor::ExtractSliceOp, tensor::InsertSliceOp,
                               tensor::CollapseShapeOp, tensor::ExpandShapeOp, ub::PoisonOp>(whole);
  // A choice by a condition per element is no choice of whole arrays.
  target.addDynamicallyLegalOp<arith::SelectOp>([&converter](arith::SelectOp select) {
    return isa<ShapedType>(select.getCondition().getType()) ||
           converter.isLegal(select.getOperation());
  });
  target.addDynamicallyLegalOp<ArrayYieldOp>([&converter](ArrayYieldOp yield) {
    if (isa<ArrayUpdateOp>(yield->getParentOp()))
      return true;
    return converter.isLegal(yield.getOperation()) &&
           llvm::none_of(yield.getValues().getTypes(), [](Type type) { return recordOf(type); });
  });
}

namespace {

struct Columns : idr::impl::IdrColumnsBase<Columns> {
  void runOnOperation() override {
    MLIRContext *ctx = &getContext();
    ColumnConverter converter;
    RewritePatternSet patterns(ctx);
    ConversionTarget target(*ctx);
    populateColumnPatterns(converter, patterns, target);
    if (failed(applyPartialConversion(getOperation(), target, std::move(patterns)))) {
      getOperation()->emitError("internal error: idr-columns: an array of records was left "
                                "neither held as its columns nor gathered");
      signalPassFailure();
    }
  }
};

} // namespace

} // namespace idr::columns
