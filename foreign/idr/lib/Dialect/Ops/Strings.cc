// The string ops: the builders that walk a list, the rules and ranges of
// the others, and when an index or a head may run before its guard.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

LogicalResult StrPackOp::verify() {
  return listCons(*this, getList().getType(), IntegerType::get(getContext(), 32)) ? success()
                                                                                 : failure();
}

LogicalResult StrConcatOp::verify() {
  return listCons(*this, getList().getType(), StrType::get(getContext())) ? success() : failure();
}

Type PutListOp::getElementType() {
  if (DataOp data = lookupData(*this, unrestricted(getList().getType())))
    for (CtorOp ctor : data.getCtors())
      if (ctor.getFieldTypes().size() == 2)
        return ctor.getFieldType(0);
  return {};
}

// A list pack or concat walks.
LogicalResult PutListOp::verify() {
  Type element = getElementType();
  if (!isa_and_nonnull<StrType>(element) && element != IntegerType::get(getContext(), 32))
    return emitOpError("writes a list of characters or of strings, not ") << getList().getType();
  return listCons(*this, getList().getType(), element) ? success() : failure();
}

LogicalResult StrShowOp::verify() {
  if (isa<FloatType>(getValue().getType()) && getIsSigned())
    return emitOpError("shows a Double, which has no signedness");
  return success();
}

void StrLengthOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(64, 0, INT64_MAX));
}

// An index past the string's end reads outside it, so it stays below its
// guard against this string's length, or below the path that proved the
// guard away.
Speculation::Speculatability StrIndexOp::getSpeculatability() {
  return checkSpeculatability(*this, getIndexMutable().getOperandNumber());
}

Speculation::Speculatability StrHeadOp::getSpeculatability() {
  return checkSpeculatability(*this, getStrMutable().getOperandNumber());
}
