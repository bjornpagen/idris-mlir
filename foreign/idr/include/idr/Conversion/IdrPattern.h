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

namespace idr::conversion {

// The benefit of a pattern that lowers an op its own way where a more
// general one also would: an op on buffers whose meaning is the runtime's
// ahead of upstream's lowering of the op.
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

} // namespace idr::conversion

#endif // IDR_CONVERSION_IDRPATTERN_H
