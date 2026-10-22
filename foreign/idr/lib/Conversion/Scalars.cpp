// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the crashes (of a cause, of the program's own text), of a
// trusted library's IO run for a pure value, and of every op of inline
// arithmetic, whose arith is its meaning over an IR builder
// (Numeric/Trait.h): one pattern for all of them, so no division, shift or
// char conversion is spelt here.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A crash of a cause of the closed set at its site: the runtime's crash,
// which does not return, then the end of the region, which nothing after it
// reaches.
struct LowerCrash : IdrPattern<CrashCauseOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashCauseOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crash(rewriter, op.getLoc(), op.getCause(), op.getSite());
    rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
    return success();
  }
};

// A trusted library's crash of a string it computed, at its site.
struct LowerCrashMessage : IdrPattern<CrashMessageOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashMessageOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crashWith(rewriter, op.getLoc(), adaptor.getMessage(), op.getSite());
    rewriter.replaceOpWithNewOp<ub::UnreachableOp>(op);
    return success();
  }
};

// The IO a trusted library runs for a pure value runs where the value is
// demanded: its region in place of the op, and the values its yield gives in
// place of the op's results. Its effects were ordered by its row up to here;
// what is left is the code.
struct LowerUnsafeRun : IdrPattern<IoUnsafeRunOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(IoUnsafeRunOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Block &body = op.getBody().front();
    Operation *yield = body.getTerminator();
    SmallVector<Value> results(yield->getOperands());
    rewriter.inlineBlockBefore(&body, op);
    rewriter.eraseOp(yield);
    rewriter.replaceOp(op, results);
    return success();
  }
};

// An op of inline arithmetic as its meaning over arith.
template <typename OpT>
struct LowerInline : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, OpT::expand(rewriter, op.getLoc(), adaptor.getOperands()));
    return success();
  }
};

// Every op whose meaning is inline arithmetic, by its trait: an op the
// specification gives such a meaning cannot lack its expansion.
template <typename... Ops>
void addInline(RewritePatternSet &patterns, const TypeConverter &converter,
               const Layouts &layouts, Runtime &runtime) {
  auto add = [&]<typename OpT>() {
    if constexpr (numeric::InlineOp<OpT>)
      patterns.add<LowerInline<OpT>>(converter, patterns.getContext(), layouts, runtime);
  };
  (add.template operator()<Ops>(), ...);
}

} // namespace

void populateScalarPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCrash, LowerCrashMessage, LowerUnsafeRun>(
      converter, patterns.getContext(), layouts, runtime);
  addInline<
#define GET_OP_LIST
#include "idr/IR/IdrOps.cpp.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
