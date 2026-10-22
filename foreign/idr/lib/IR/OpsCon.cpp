// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What builds a constructor value: idr.data.con. It reads its constructor
// off its result's type, refined to it, and the fields off the type's
// declaration at its application, so nothing here reads the module or looks
// a constructor up by name. What reads a constructor value is
// OpsConReads.cpp's; what writes one into a cell counting gives it is
// counting's.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// The data type of a value of `type`, refined to the one constructor whose
// fields it determines; null for any other type.
DataType builtData(Type type) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || !data.singleTag() || !data.determinedFields(*data.singleTag()))
    return DataType();
  return data;
}

} // namespace

DataType DataConOp::getDataType() { return builtData(getResult().getType()); }
Tag DataConOp::getTag() { return *getDataType().singleTag(); }

// The result is refined to one constructor, which its type determines the
// binders of; the fields given are that constructor's at that application,
// each filling its field.
LogicalResult DataConOp::verify() {
  DataType data = getDataType();
  if (!data)
    return emitOpError("builds ") << getResult().getType()
                                  << ", which is refined to no one constructor whose binders it "
                                  << "determines";
  SmallVector<Type> fields = *data.determinedFields(getTag());
  if (getFields().size() != fields.size())
    return emitOpError("expects ") << fields.size() << " fields";
  std::optional<Hold> built = holdOf(getResult().getType());
  for (auto [value, expected] : llvm::zip_equal(getFields(), fields))
    if (!fillsField(value.getType(), expected, built))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

// A constructor of constants is a constant, where nothing reads which value
// it is: not a memo cell, which a force writes, nor a value of a family
// rebuilt in place or one used once, each of which is its own. A poison
// field is the program's value where control never arrives, which no
// constant holds, so the constructor stays an op around it.
OpFoldResult DataConOp::fold(FoldAdaptor adaptor) {
  DataType data = getDataType();
  if (data.kind() != MemberKind::Data || data.promise() == Promise::InPlace ||
      usesOf(getResult().getType()) == Uses::Once)
    return {};
  for (auto [field, operand] : llvm::zip_equal(adaptor.getFields(), getFields()))
    if (!field || !ConstantOp::isBuildableWith(field, operand.getType()))
      return {};
  return ConAttr::get(getContext(), data, ArrayAttr::get(getContext(), adaptor.getFields()));
}
