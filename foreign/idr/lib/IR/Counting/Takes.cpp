// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value taken apart, and one rebuilt in the cell its token holds: a take
// of a value from its cell (count.take, fused with its recycle in
// count.take_into), an unpack of a value held in place (count.unpack), the
// one run-time test of sharing (count.match_unique), and the rebuild the
// in-place rule decided (token.rebuild). Each reads its constructor off a
// type refined to it and the fields off the declaration at its
// application, each at the type a read of it gives, so nothing here reads
// the module or names a constructor. An unpack passes a scoped value's
// fields through, so it states the lifetime of each scoped field, one step
// from it. Here too is where reuse finds a cell: a take whose cell its
// free empties and a drop that can become such a take, each a source of a
// dead cell, and the fresh cell a token of its size may stand in for.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// What the operands ask
//===----------------------------------------------------------------------===//

namespace {

// The data type a value of `type` is, refined to the one constructor whose
// fields it determines; null for any other type.
DataType refinedData(Type type) {
  DataType data = dataTypeOf(type);
  if (!data || !data.singleTag() || !data.determinedFields(*data.singleTag()))
    return DataType();
  return data;
}

} // namespace

namespace idr {

// A memo cell is never taken apart: a force changes its constructor while
// references to it live.
bool isTakeable(Type value) {
  DataType data = refinedData(value);
  return data && isCountedValue(value) && buildsCell(value, *data.singleTag()) && !data.memo();
}

bool isUnpackable(Type value) {
  DataType data = refinedData(value);
  return data && !buildsCell(value, *data.singleTag());
}

} // namespace idr

//===----------------------------------------------------------------------===//
// Take, unpack, take_into
//===----------------------------------------------------------------------===//

namespace {

// The data type and constructor a take apart reads off its value.
template <typename Op>
DataType takenData(Op op) {
  return cast<DataType>(unrestricted(op.getValue().getType()));
}

// The token a take gives of a value of `type`: used once; it holds its cell
// where the type claims its own cells unshared, the taken cell first among
// them, and may be null otherwise.
Type tokenOf(Type type) {
  DataType data = cast<DataType>(unrestricted(type));
  Unique holds = claims(type, Unique::Self) ? Unique::Deep : Unique::None;
  return graded(Grade{Uses::Once, Hold::counted(holds)}, ReuseTokenType::of(data));
}

// The fields of a value of `type` taken apart, each at the type a read of
// it gives (fieldReadType), so a field moved out and a field read are one
// value's type, and placement may put the one where the other was: a
// constructor's field claims what the value's claim reaches into it, so a
// part of a `unique deep` value taken at a linear position is `unique
// deep`, and one taken at many uses claims nothing, as it may be
// duplicated; a frame's field is the whole grade the frame keeps it at.
LogicalResult fieldsOf(std::optional<Location> location, Type type,
                       SmallVectorImpl<Type> &fields) {
  DataType data = refinedData(type);
  if (!data)
    return emitOptionalError(location, "takes apart ", type,
                             ", which is refined to no one constructor whose binders it "
                             "determines");
  unsigned count = static_cast<unsigned>(data.ctor(*data.singleTag()).fields.size());
  for (unsigned index = 0; index < count; ++index)
    fields.push_back(*fieldReadType(type, index));
  return success();
}

} // namespace

DataType CountTakeOp::getDataType() { return takenData(*this); }
Tag CountTakeOp::getTag() { return *getDataType().singleTag(); }

LogicalResult CountTakeOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                            Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type value = adaptor.getValue().getType();
  if (!isTakeable(value))
    return emitOptionalError(location, "takes ", value,
                             ", which is no counted value refined to a constructor with a cell");
  inferred.push_back(tokenOf(value));
  return fieldsOf(location, value, inferred);
}

DataType CountUnpackOp::getDataType() { return takenData(*this); }
Tag CountUnpackOp::getTag() { return *getDataType().singleTag(); }

LogicalResult CountUnpackOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                              Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  return fieldsOf(location, adaptor.getValue().getType(), inferred);
}

// A field read at the value's hold lives where the value does, so each
// scoped field states the value's lifetime. A frame's field keeps whatever
// lifetime the frame was given it in, which only the frame's maker knows:
// it states those with the builder that takes them.
void CountUnpackOp::build(OpBuilder &, OperationState &state, Value value) {
  state.addOperands(value);
  SmallVector<Type> fields;
  if (failed(fieldsOf(state.location, value.getType(), fields)))
    mlir::detail::reportFatalInferReturnTypesError(state);
  if (Value lifetime = lifetimes::statedLifetime(value))
    for (Type field : fields)
      if (freedBy(field, Release::Scoped))
        state.addOperands(lifetime);
  state.addTypes(fields);
}

Value CountUnpackOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void CountUnpackOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// One lifetime per scoped field, in field order.
LogicalResult CountUnpackOp::verify() { return lifetimes::verifyOuters(*this, 0); }

DataType CountTakeIntoOp::getDataType() { return takenData(*this); }
Tag CountTakeIntoOp::getTag() { return *getDataType().singleTag(); }

void CountTakeIntoOp::build(OpBuilder &, OperationState &state, CellType cell, Value value) {
  state.addOperands(value);
  state.addTypes(cell);
  SmallVector<Type> fields;
  if (failed(fieldsOf(state.location, value.getType(), fields)))
    mlir::detail::reportFatalInferReturnTypesError(state);
  state.addTypes(fields);
}

//===----------------------------------------------------------------------===//
// Where reuse finds a cell, and where it may fill one
//===----------------------------------------------------------------------===//

// A take whose token's one user frees it empties a cell nothing needs.
DataType CountTakeOp::getFreedCellType() {
  Value token = getToken();
  if (token.hasOneUse() && isa<TokenFreeOp>(*token.user_begin()))
    return getDataType();
  return DataType();
}

// The take already gives the token; its free goes, so the cell is kept.
// The free may be the op right after the take, so the builder is set past
// the take only once the free is gone.
Value CountTakeOp::takeFreedToken(OpBuilder &builder) {
  assert(getFreedCellType() && "a take gives its token only where its free is the token's one user");
  Value token = getToken();
  (*token.user_begin())->erase();
  builder.setInsertionPointAfter(*this);
  return token;
}

// A drop of a value whose type fixes a constructor that has a cell of its
// own can become the take of that cell, but for a memo's, which is never
// taken apart.
DataType CountDropOp::getFreedCellType() {
  Type value = getValue().getType();
  DataType data = dataTypeOf(value);
  std::optional<Tag> tag = data ? data.singleTag() : std::nullopt;
  if (tag && !data.memo().has_value() && buildsCell(value, *tag))
    return data;
  return DataType();
}

// The drop becomes the take of its value, built where the builder stands,
// right after it: each counted field is dropped there and the emptied cell
// kept. The builder stays past what was built, the drop gone.
Value CountDropOp::takeFreedToken(OpBuilder &builder) {
  assert(getFreedCellType() && "a drop gives a token only of a cell its type fixes");
  Location loc = getLoc();
  auto taken = CountTakeOp::create(builder, loc, getValue());
  for (Value field : taken.getFields())
    if (freedBy(field.getType(), Release::Counted))
      CountDropOp::create(builder, loc, field);
  erase();
  return taken.getToken();
}

// A fresh cell, which a dead cell of its size may be recycled into.
CellType CellNewOp::getFilledCellType() { return getCell().getType(); }

//===----------------------------------------------------------------------===//
// The match on uniqueness
//===----------------------------------------------------------------------===//

// Both regions entered from the op, exactly one of them per run, each
// giving the op's results.
void CountMatchUniqueOp::getSuccessorRegions(RegionBranchPoint point,
                                             SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent()) {
    regions.emplace_back(&getUnique());
    regions.emplace_back(&getShared());
    return;
  }
  regions.emplace_back(getOperation());
}

// The value is forwarded into the shared region; the unique region's
// arguments are the op's own, made of the value's cell.
OperandRange CountMatchUniqueOp::getEntrySuccessorOperands(RegionSuccessor successor) {
  OperandRange operands = getOperation()->getOperands();
  return successor.getSuccessor() == &getShared() ? operands : operands.take_front(0);
}

ValueRange CountMatchUniqueOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getOperation()->getResults();
  if (successor.getSuccessor() == &getUnique())
    return ValueRange();
  return getShared().getArguments();
}

void CountMatchUniqueOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                                   SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(0, 1);
  bounds.emplace_back(0, 1);
}

// The unique region binds the cell's token, which holds it, and the fields
// moved out at the types a read gives; the shared region binds the value.
LogicalResult CountMatchUniqueOp::verifyRegions() {
  Type value = getValue().getType();
  SmallVector<Type> unique{graded(Grade{Uses::Once, Hold::counted(Unique::Deep)},
                                  ReuseTokenType::of(cast<DataType>(unrestricted(value))))};
  if (failed(fieldsOf(getLoc(), value, unique)))
    return failure();
  if (!llvm::equal(getUnique().front().getArgumentTypes(), unique))
    return emitOpError("binds in its unique region other than the token that holds the cell "
                       "and the fields of ")
           << value;
  if (!llvm::equal(getShared().front().getArgumentTypes(), ArrayRef<Type>(value)))
    return emitOpError("binds in its shared region other than the value ") << value;
  return success();
}

//===----------------------------------------------------------------------===//
// The rebuild in place
//===----------------------------------------------------------------------===//

// The in-place promise rebuilds in a cell its check made the holder's: the
// token holds its cell; the value is counted, built in it, each field
// filling the constructor's.
LogicalResult TokenRebuildOp::verify() {
  if (!claims(getToken().getType(), Unique::Self))
    return emitOpError("rebuilds in a token that may be null");
  Type result = getResult().getType();
  DataType data = refinedData(result);
  if (!data || !buildsCell(result, *data.singleTag()))
    return emitOpError("rebuilds ") << result
                                    << ", which is refined to no constructor with a cell";
  if (!freedBy(result, Release::Counted))
    return emitOpError("rebuilds ") << result << ", which its count does not free";
  SmallVector<Type> fields = *data.determinedFields(*data.singleTag());
  if (fields.size() != getFields().size())
    return emitOpError("is given ") << getFields().size() << " fields, not " << fields.size();
  std::optional<Hold> hold = holdOf(result);
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getFields(), fields)))
    if (!fillsField(std::get<0>(pair).getType(), std::get<1>(pair), hold))
      return emitOpError("field ") << index << " has type " << std::get<0>(pair).getType()
                                   << ", which does not fill " << std::get<1>(pair);
  return success();
}
