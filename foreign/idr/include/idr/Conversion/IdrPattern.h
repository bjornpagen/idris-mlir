// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The base of phase 2's patterns: the layouts and the runtime they lower
// with.

#ifndef IDR_CONVERSION_IDRPATTERN_H
#define IDR_CONVERSION_IDRPATTERN_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/Runtime.h"

#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

namespace idr::conversion {

// The benefit of a pattern that lowers an op its own way where a more
// general one also would: a big op whose small case is inline ahead of the
// call of its runtime function, and an op on buffers whose meaning is the
// runtime's ahead of upstream's lowering of the op.
inline constexpr unsigned ownLowering = 2;

// Each pattern instantiates the template, so its body is here.
template <typename OpT>
struct IdrPattern : mlir::OpConversionPattern<OpT> {
  IdrPattern(const mlir::TypeConverter &converter, mlir::MLIRContext *ctx, const Layouts &l,
             Runtime &r, mlir::PatternBenefit benefit = 1)
      : mlir::OpConversionPattern<OpT>(converter, ctx, benefit), layouts(l), runtime(r) {}
  const Layouts &layouts;
  Runtime &runtime;
};

// An op whose meaning is its operand. Linearity, a view, a forgotten
// exclusive grade and a natural as the Integer it is have no runtime form,
// so the value is itself.
template <typename OpT>
struct LowerAsItself : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  mlir::LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                      mlir::ConversionPatternRewriter &rewriter) const override {
    mlir::ValueRange value = adaptor.getOperands().front();
    rewriter.replaceOpWithMultiple(op, {llvm::SmallVector<mlir::Value>(value)});
    return mlir::success();
  }
};

} // namespace idr::conversion

#endif // IDR_CONVERSION_IDRPATTERN_H
