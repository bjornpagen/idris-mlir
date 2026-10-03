// The string ops: the builders that walk a list, and the rules, ranges and
// crashes of the others.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

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

// In range when both operands are constants and the index is below the
// number of characters (UTF-8 lead bytes).
std::optional<StringRef> StrIndexOp::getCrashCause() {
  StringAttr str;
  APInt index;
  if (matchPattern(getStr(), m_Constant(&str)) && matchPattern(getIndex(), m_ConstantInt(&index))) {
    auto characters = static_cast<uint64_t>(
        llvm::count_if(str.getValue(), [](char c) { return (c & 0xC0) != 0x80; }));
    if (!index.isNegative() && index.getZExtValue() < characters)
      return std::nullopt;
  }
  return StringRef("string index out of range");
}
