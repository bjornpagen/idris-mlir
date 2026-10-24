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
#include "idr/IR/Fold.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>

// Whether the program's references are counted (StageCounting).
#include "idr/IR/Generated/StageFacts.h.inc"

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

// Its result is its constructor applied to its fields, whatever they are.
Structure DataConOp::getStructure() { return structural::Built{getTag(), getFields()}; }

// The cell is new, so nothing but its fields shares what the value
// reaches: the most a fresh value built of those fields may claim, each
// field bounding it as the local rule says (freshest, the grade's tables of
// it), at the uses its grade gives it, so one used many times gives nothing,
// its other uses reaching its cells too; a field that holds no reference
// bounds nothing. The specification's freshClaim, by which the frontend
// writes the claim too. It reads types alone, so after counting it still
// reads a part's grade as counting found it: the claim it gives is then no
// more than the verifier's rule proves, and never more than the value holds.
Unique DataConOp::freshClaim(DataType carrier, TypeRange fields) {
  Unique claim = Unique::Deep;
  for (auto [declared, field] : llvm::zip_equal(carrier.ctor(*carrier.singleTag()).fields, fields))
    if (std::optional<Hold> hold = holdOf(field))
      claim = ownership::lesser(
          claim, ownership::freshest(fieldReach(declared), usesOf(field), hold->claim()));
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

// Moving it where it would not have run would use a field used once on a
// path that keeps that field for itself; and, once the program's references
// are counted, it would move a field's reference into the value on such a
// path, as counting's rule says (referenceAt), whatever the field's uses.
// Before counting no reference is placed yet, so a field used many times
// takes its reference wherever the value ends up. The rule's moves are
// read once for every field.
Speculation::Speculatability DataConOp::getSpeculatability() {
  for (OpOperand &field : getFieldsMutable())
    if (usesOf(field.get().getType()) == Uses::Once)
      return Speculation::NotSpeculatable;
  auto program = (*this)->getParentOfType<ProgramOp>();
  assert(program && "a constructor stands in a program, whose stage says what is counted");
  if (countingAt[program.getStage()] == StageCounting::Uncounted)
    return Speculation::Speculatable;
  llvm::SmallBitVector moved = movedOn(getOperation());
  for (OpOperand &field : getFieldsMutable())
    if (moved.test(field.getOperandNumber()))
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

// Its meaning's attribute instance (Ops/Folds.h).
OpFoldResult DataConOp::fold(FoldAdaptor adaptor) {
  fold::InParts where(getContext());
  std::optional<Attribute> folded = meaning(where, *this, adaptor.getOperands());
  return folded ? OpFoldResult(*folded) : OpFoldResult();
}
