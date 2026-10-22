// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The string ops: the ranges of those that give a number, and the folds of
// the two builders that call no runtime function of their own, a list's
// pack and concat, which build their string once from a constant list.
// Every other string op folds through its runtime function (Fold.h); the
// rewrites of output and of a head are rules of the specification.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Ranges.h"

#include <cstdint>

using namespace mlir;
using namespace idr;

void StrLengthOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 0, INT64_MAX));
}

// A scalar value, or 0 at the end.
void StrScalarAtOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, 0, 0x10FFFF));
}

// One to four bytes, of any i32: one that is no scalar value has the
// length its encoding has.
void StrScalarBytesOp::inferResultRanges(ArrayRef<ConstantIntRanges>,
                                         SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 1, 4));
}

OpFoldResult StrPackOp::fold(FoldAdaptor adaptor) {
  return fold::stringOfList(getContext(), adaptor.getList());
}

OpFoldResult StrConcatOp::fold(FoldAdaptor adaptor) {
  return fold::stringOfList(getContext(), adaptor.getList());
}
