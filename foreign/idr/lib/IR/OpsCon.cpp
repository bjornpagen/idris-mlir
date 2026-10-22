// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What builds a constructor value: idr.data.con. It reads its constructor
// off its result's type, refined to it, and the fields off the type's
// declaration at its application, so nothing here reads the module or looks
// a constructor up by name. What reads a constructor value is
// OpsConReads.cpp's; what writes one into a cell counting gives it is
// counting's.

#include "idr/Analysis/Ownership/Local.h"
#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

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

// The cell is new, so nothing but its fields shares what the value
// reaches: the most a fresh value built of those fields may claim, each
// field bounding it as the local rule says (freshest, from the grade's read
// table), a field that holds no reference bounding nothing.
Unique DataConOp::freshClaim(DataType carrier, TypeRange fields) {
  Unique claim = Unique::Deep;
  for (auto [declared, field] : llvm::zip_equal(carrier.ctor(*carrier.singleTag()).fields, fields)) {
    std::optional<Hold> hold = holdOf(field);
    claim = ownership::lesser(
        claim, ownership::freshest(fieldReach(declared), hold ? hold->claim() : Unique::Deep));
  }
  return claim;
}

// A fresh value: the carrier at `uses`, counted where it holds references,
// claiming what its fields leave unshared.
void DataConOp::build(OpBuilder &builder, OperationState &state, DataType carrier, Uses uses,
                      ValueRange fields) {
  std::optional<Hold> hold;
  if (holdsReferences(carrier))
    hold = Hold::counted(freshClaim(carrier, fields.getTypes()));
  build(builder, state, graded(Grade{uses, hold}, carrier), fields);
}

// A value of `result`, which states no lifetime: a scoped one has its
// lifetime stated by the step that decides lifetimes, one its scoped fields
// all outlive.
void DataConOp::build(OpBuilder &builder, OperationState &state, Type result, ValueRange fields) {
  build(builder, state, result, fields, ValueRange());
}

Value DataConOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }
void DataConOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// Moving it where it would not have run would take a field over, or use a
// field used once, on a path that keeps that field for itself.
Speculation::Speculatability DataConOp::getSpeculatability() {
  for (OpOperand &field : getFieldsMutable())
    if (effects::consumes(field) || usesOf(field.get().getType()) == Uses::Once)
      return Speculation::NotSpeculatable;
  return Speculation::Speculatable;
}

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
  for (auto [value, expected] : llvm::zip_equal(getFields(), fields)) {
    if (!fillsField(value.getType(), expected, built))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
    // A frame gives each value back at the hold its field declares, so the
    // value pushed stands where that hold is asked, or the pop would claim
    // what the push never had.
    std::optional<Hold> kept = holdOf(expected);
    std::optional<Hold> given = holdOf(value.getType());
    if (data.kind() == MemberKind::Frames && kept && !(given && given->fits(*kept)))
      return emitOpError("pushes ") << value.getType() << " into a frame that keeps it as "
                                    << expected;
  }
  return lifetimes::verifyOuters(*this, 0);
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
