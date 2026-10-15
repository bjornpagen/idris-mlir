// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The conversion's patterns for idr.call and idr.return: each moves its
// values between its own slots and those of the function it calls or
// returns from, which are keyed by the function, not by its types, and
// read from the decision's signature table.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Flow.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/Transforms/DialectConversion.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// A call passes each argument in its callee's parameter slot and returns
// its callee's result, then moves it into its own slot. The call is the
// same call of the same callee, so it keeps what it carries, its effects
// among them.
struct CallPattern : SlotPattern<CallOp> {
  using SlotPattern::SlotPattern;

  LogicalResult matchAndRewrite(CallOp call, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const Signature &sig = slots().signature(call.getCalleeAttr().getAttr());
    SmallVector<Value> operands;
    if (failed(converter().coerceOperands(rewriter, call, adaptor.getOperands(), operands)))
      return failure();
    auto made = CallOp::create(rewriter, call.getLoc(), sig.converted.getResults(),
                               call.getCalleeAttr(), operands, call.getArgAttrsAttr(),
                               call.getResAttrsAttr(), call.getEffectsAttr());
    SmallVector<Value> results;
    for (auto [j, result] : llvm::enumerate(call.getResults())) {
      Value value = made.getResult(static_cast<unsigned>(j));
      if (isKeyed(result.getType())) {
        value = converter().coerce(rewriter, call.getLoc(), value, sig.results[j],
                                   converter().keyOf(result), converter().typeOf(result));
        if (!value)
          return failure();
      }
      results.push_back(value);
    }
    rewriter.replaceOp(call, results);
    return success();
  }
};

// A return moves each value into its function's result slot. It is made
// anew rather than changed in place: only the uses the function had owe a
// move, so the new op is legal once it has its operands.
struct ReturnPattern : SlotPattern<ReturnOp> {
  using SlotPattern::SlotPattern;

  LogicalResult matchAndRewrite(ReturnOp ret, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    SmallVector<Value> operands;
    if (failed(converter().coerceOperands(rewriter, ret, adaptor.getOperands(), operands)))
      return failure();
    rewriter.replaceOpWithNewOp<ReturnOp>(ret, operands);
    return success();
  }
};

} // namespace

void populateCallOpTypeConversionPattern(RewritePatternSet &patterns,
                                         const SlotTypeConverter &converter) {
  patterns.add<CallPattern>(converter, patterns.getContext());
}

void populateReturnOpTypeConversionPattern(RewritePatternSet &patterns,
                                           const SlotTypeConverter &converter) {
  patterns.add<ReturnPattern>(converter, patterns.getContext());
}

} // namespace idr::defunctionalize
