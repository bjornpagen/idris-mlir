// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The string ops: the builders that walk a list, the rules and ranges of
// the others, when an index or a head may run before its guard, and the
// output and head canonicalizations. A list op's list is base's, whose
// shape its data type says.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/PatternMatch.h"

#include <cstdint>

using namespace mlir;
using namespace idr;

namespace {

// A list the builders walk is base's list in a box, whose data type is of
// kind `list` and so a nil and then a cons of an element and the list; its
// element is one of `elements`.
LogicalResult verifyList(Operation *op, Value list, ArrayRef<Type> elements) {
  DataType data = dataTypeOf(list.getType());
  if (!isBoxed(list.getType()) || !data || data.getKind() != SumKind::BaseList)
    return op->emitOpError("walks base's list, a box of a nil and a cons, not ") << list.getType();
  if (!llvm::is_contained(elements, data.getListElement()))
    return op->emitOpError("walks a list of ") << data.getListElement() << ", not of "
                                               << elements;
  return success();
}

} // namespace

LogicalResult StrPackOp::verify() {
  return verifyList(*this, getList(), {IntegerType::get(getContext(), 32)});
}

LogicalResult StrConcatOp::verify() {
  return verifyList(*this, getList(), {StrType::get(getContext())});
}

// A list pack or concat walks.
LogicalResult PutListOp::verify() {
  return verifyList(*this, getList(),
                    {IntegerType::get(getContext(), 32), StrType::get(getContext())});
}

LogicalResult StrShowOp::verify() {
  if (isa<FloatType>(getValue().getType()) && getIsSigned())
    return emitOpError("shows a Double, which has no signedness");
  return success();
}

void StrLengthOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 0, INT64_MAX));
}

// A scalar value, or 0 at the end.
void StrScalarAtOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, 0, 0x10FFFF));
}

// An offset within the string's bytes.
void StrScalarEndOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(64, 0, INT64_MAX));
}

// An index past the string's end reads outside it, so it stays below its
// guard against this string, or below the path that proved the guard away.
Speculation::Speculatability StrIndexOp::getSpeculatability() {
  return guardedSpeculatability<CheckInBoundsOp>(getIndex(), getStr());
}

Speculation::Speculatability StrHeadOp::getSpeculatability() {
  return guardedSpeculatability<CheckNonemptyOp>(getStr());
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

// Whether output writes a string in the pieces it is built of, where the
// output patterns take it apart.
bool idr::writtenInPieces(Value str) {
  Operation *builder = str.getDefiningOp();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(builder))
    return true;
  return isa_and_nonnull<StrPackOp, StrConcatOp>(builder) && str.hasOneUse();
}
