// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-lower tells LLVM about the values functions take and return,
// which the types say and the LLVM types no longer do.

#ifndef IDR_CONVERSION_FACTS_H
#define IDR_CONVERSION_FACTS_H

#include "idr/IR/Layout.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"

namespace idr::conversion {

// The conversion of a function's signature, as upstream's for a function
// op, which writes the facts of each parameter's first component where the
// signature conversion puts it, and of a result that is one cell pointer:
//   - a value whose type is a cell pointer (a box, a string; after
//     idr-defunctionalize every closure and suspension is a box) points to
//     a cell, never null, aligned to a cell's start, with at least its
//     header to read (`nonnull`, `align`, `dereferenceable`): poison of one
//     is the static cell `nothing`, so no parameter is ever null;
//   - an unboxed sum's tag is in [0, n) for n constructors (`range`).
// It replaces upstream's signature conversion of func.func, on every worker
// of the conversion.
void populateSignaturePatterns(mlir::RewritePatternSet &patterns,
                               const mlir::TypeConverter &converter, const Layouts &layouts);

} // namespace idr::conversion

#endif // IDR_CONVERSION_FACTS_H
