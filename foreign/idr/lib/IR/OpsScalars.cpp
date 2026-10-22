// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the first character of a number's text, which the runtime's
// printers give and no meaning of ours computes: what each printer can
// begin with. Every other scalar op says nothing here: Euclidean division,
// the shifts and the char conversions fold, infer their ranges and expand
// through their trait (Numeric/Trait.h), and a Double's truncation and the
// heads fold through their runtime function (Fold.h).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

using namespace mlir;
using namespace idr;

// '-', a digit, or the first letter of `inf` or `nan`.
void F64HeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, '-', 'n'));
}

// '-' or a digit.
void IntHeadSOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, '-', '9'));
}

// A digit.
void IntHeadUOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, '0', '9'));
}
