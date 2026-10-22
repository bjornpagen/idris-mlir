// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What reads a constructor value: idr.data.field, a field of a value
// refined to its constructor, a total read, since the type fixes the
// constructor; and idr.data.tag, its constructor's tag. Each reads the
// fields off the value's type, at its application, so nothing here reads
// the module, looks a constructor up by name or walks to an enclosing
// match: a case binds its scrutinee refined, and a field is read from that
// value.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

std::optional<Type> idr::fieldReadType(Type value, unsigned index) {
  auto data = dyn_cast<DataType>(unrestricted(value));
  if (!data || !data.singleTag())
    return std::nullopt;
  Tag tag = *data.singleTag();
  std::optional<SmallVector<Type>> fields = data.determinedFields(tag);
  if (!fields || index >= fields->size())
    return std::nullopt;
  // Essential, two holders. A frame keeps each value at its whole grade,
  // which its field declares, and gives it back so. A constructor's field
  // holds what the value it is read from holds: how far that value's claim
  // on its own cells reaches into the field is the field's declaration's
  // (a field of its own group, or of an in_place family, keeps a `unique
  // self` claim).
  Type field = (*fields)[index];
  if (data.kind() == MemberKind::Frames)
    return field;
  return fieldType(value, unrestricted(field), usesOf(field),
                   fieldReach(data.ctor(tag).fields[index]));
}

//===----------------------------------------------------------------------===//
// idr.data.field
//===----------------------------------------------------------------------===//

DataType DataFieldOp::getDataType() { return dyn_cast<DataType>(unrestricted(getValue().getType())); }
Tag DataFieldOp::getTag() { return *getDataType().singleTag(); }

void DataFieldOp::build(OpBuilder &builder, OperationState &state, Value value, unsigned index) {
  build(builder, state, *fieldReadType(value.getType(), index), value, uint64_t{index});
}

LogicalResult DataFieldOp::verify() {
  std::optional<Type> expected = fieldReadType(getValue().getType(), getIndex());
  if (!expected)
    return emitOpError("reads field ") << getIndex() << " of " << getValue().getType()
                                       << ", which is refined to no one constructor with it";
  if (*expected != getType())
    return emitOpError("has result ") << getType() << ", but the field of a "
                                      << getValue().getType() << " is read as " << *expected;
  return success();
}

// A field of a known constructor: the field an idr.data.con was given,
// where its state still holds (a memo cell's changes) and the read takes
// it at the type it was given; a linear field moves out of the constructor,
// so only the constructor's one read takes it. Or a field of a constant,
// read in place: off a run's spine that costs nothing however long the run
// is. A constant is no linear value, so a linear field of one stays a read.
OpFoldResult DataFieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = getValue();
  if (!builtStateHolds(source, getOperation()))
    return {};
  if (auto con = source.getDefiningOp<DataConOp>()) {
    Value field = con.getFields()[index];
    if (field.getType() == getType() &&
        (usesOf(field.getType()) != Uses::Once || fieldReadOnce(con.getResult(), index)))
      return field;
    return {};
  }
  if (isLinear(getType()))
    return {};
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  return con ? con.getField(index) : Attribute();
}

//===----------------------------------------------------------------------===//
// idr.data.tag
//===----------------------------------------------------------------------===//

// The one constructor the type leaves possible; else the constructor of a
// constant, or of the idr.data.con that built the value where its state
// still holds.
OpFoldResult DataTagOp::fold(FoldAdaptor adaptor) {
  auto data = dyn_cast<DataType>(unrestricted(getValue().getType()));
  if (!data)
    return {};
  std::optional<Tag> tag = data.singleTag();
  if (!tag && builtStateHolds(getValue(), getOperation())) {
    if (auto con = getValue().getDefiningOp<DataConOp>())
      tag = con.getTag();
    else if (auto constant = dyn_cast_or_null<ConAttr>(adaptor.getValue()))
      tag = constant.getTag();
  }
  if (!tag)
    return {};
  return IntegerAttr::get(getType(), static_cast<int64_t>(*tag));
}

// Within its possible constructors' tags: the least and the most of them.
void DataTagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  auto data = dyn_cast<DataType>(unrestricted(getValue().getType()));
  unsigned width = getType().getIntOrFloatBitWidth();
  if (!data || data.possibleTags().empty()) {
    setResultRange(getResult(), ConstantIntRanges::maxRange(width));
    return;
  }
  const families::TagSet &possible = data.possibleTags();
  auto low = static_cast<uint64_t>(possible.front());
  auto high = static_cast<uint64_t>(possible[possible.size() - 1]);
  setResultRange(getResult(), idr::ranges::nonNegative(width, low, high));
}
