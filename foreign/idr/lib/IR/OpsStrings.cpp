// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The string ops: the ranges of those that give a number, and the output
// and head canonicalizations.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"

#include "mlir/IR/PatternMatch.h"

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

// Output and the first character of a string being built are taken apart
// into the pieces it is built of; output of a list takes one step of the
// list it meets.
void PutStrOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addPutStrPatterns(results, context);
}

void PutListOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addPutListPatterns(results, context);
}

void StrHeadOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addStrHeadPatterns(results, context);
}
