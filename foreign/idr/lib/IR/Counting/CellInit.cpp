// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The init of a cell (idr.cell.init): the fields of the cell's constructor
// written into it, each a field given or a hole written later through its
// destination, giving the value. Its results follow from the cell's type,
// the fields and the holes, and its directives write what follows as
// nothing; the destination of a hole is the one rule idr-trmc reads too.
// The constructor is read off the cell's type and the fields off the
// declaration at its application, so nothing here reads the module.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// What the init gives
//===----------------------------------------------------------------------===//

namespace {

// The fields of `cell`'s constructor at its application, read once per
// question. Failure, after an error at `location` when there is one, where
// the cell's type does not determine its constructor's binders.
FailureOr<SmallVector<Type>> constructorFields(std::optional<Location> location, CellType cell) {
  DataType data = cell.getData();
  std::optional<SmallVector<Type>> fields = data.determinedFields(cell.getTag());
  if (!fields)
    return emitOptionalError(location, "writes a cell of ", data,
                             ", whose constructor's binders it does not determine");
  return std::move(*fields);
}

// The destination of hole `hole` of a constructor of `fields`: written
// through, once, with a value of the field's declared type at its grade,
// so a quantity or a claim the declaration states is kept through the
// write. What a hole may hold is the destination type's own rule, asked
// here and stated nowhere else.
FailureOr<DestType> destAt(std::optional<Location> location, MLIRContext *context,
                           ArrayRef<Type> fields, int32_t hole) {
  if (hole < 0 || static_cast<size_t>(hole) >= fields.size())
    return emitOptionalError(location, "has a hole at field ", hole,
                             ", which its constructor does not have");
  DestType dest = DestType::getChecked(location.value_or(UnknownLoc::get(context)), context,
                                       fields[static_cast<size_t>(hole)]);
  if (!dest)
    return failure();
  return dest;
}

// The type each of `fields` is filled with: the next field given, or, for a
// hole, what its destination's write must meet, so the value claims what
// its holes will hold. Failure, after an error at `location` when there is
// one, where the fields and holes do not fill the constructor's fields once
// each. The op may not have been verified yet, so the holes are read as
// given.
FailureOr<SmallVector<Type>> filledFields(std::optional<Location> location, CellType cell,
                                          ArrayRef<Type> fields, TypeRange given,
                                          ArrayRef<int32_t> holes) {
  SmallVector<Type> filled;
  auto next = given.begin();
  for (unsigned index = 0; index < fields.size(); ++index) {
    auto at = static_cast<int32_t>(index);
    if (llvm::is_contained(holes, at)) {
      FailureOr<DestType> dest = destAt(location, cell.getContext(), fields, at);
      if (failed(dest))
        return failure();
      filled.push_back(dest->getValue());
    } else if (next != given.end()) {
      filled.push_back(*next++);
    } else {
      return emitOptionalError(location, "is given fewer fields than its constructor has");
    }
  }
  if (next != given.end() || given.size() + holes.size() != filled.size())
    return emitOptionalError(location, "is given more fields or holes than its constructor has");
  return filled;
}

// The value a cell's init gives, at the grade it has unless another is
// written: the value as it is made, used once and counted, claiming what a
// constructor of the same fields claims (the constructor's own rule), since
// the cell is fresh, new or recycled, and nothing but its fields shares
// what the value reaches. A claim holds only at a linear position, where
// nothing duplicates the value; one used many times is written so.
FailureOr<Type> initResult(std::optional<Location> location, CellType cell, ArrayRef<Type> fields,
                           TypeRange given, ArrayRef<int32_t> holes) {
  FailureOr<SmallVector<Type>> filled = filledFields(location, cell, fields, given, holes);
  if (failed(filled))
    return failure();
  DataType data = cell.getData();
  return graded(Grade{Uses::Once, Hold::counted(DataConOp::freshClaim(data, *filled))}, data);
}

// The value and then the destination of each hole, the constructor's
// fields read once for both.
LogicalResult initTypes(std::optional<Location> location, CellType cell, TypeRange given,
                        ArrayRef<int32_t> holes, SmallVectorImpl<Type> &types) {
  FailureOr<SmallVector<Type>> fields = constructorFields(location, cell);
  if (failed(fields))
    return failure();
  FailureOr<Type> value = initResult(location, cell, *fields, given, holes);
  if (failed(value))
    return failure();
  types.push_back(*value);
  for (int32_t hole : holes) {
    FailureOr<DestType> dest = destAt(location, cell.getContext(), *fields, hole);
    if (failed(dest))
      return failure();
    types.push_back(*dest);
  }
  return success();
}

ArrayRef<int32_t> holesOf(DenseI32ArrayAttr holes) {
  return holes ? holes.asArrayRef() : ArrayRef<int32_t>();
}

// The value given for field `index` of a constructor built with `fields`
// and `holes`, ascending, or null for a hole; and the destination of a
// hole, or null for a field given.
Value givenField(ValueRange fields, ArrayRef<int32_t> holes, unsigned index) {
  const int32_t *hole = llvm::lower_bound(holes, static_cast<int32_t>(index));
  if (hole != holes.end() && *hole == static_cast<int32_t>(index))
    return Value();
  return fields[index - static_cast<unsigned>(hole - holes.begin())];
}

Value holeDest(ResultRange dests, ArrayRef<int32_t> holes, unsigned index) {
  const int32_t *hole = llvm::lower_bound(holes, static_cast<int32_t>(index));
  if (hole == holes.end() || *hole != static_cast<int32_t>(index))
    return Value();
  return dests[static_cast<unsigned>(hole - holes.begin())];
}

} // namespace

FailureOr<DestType> idr::destOf(std::optional<Location> location, CellType cell, int32_t hole) {
  FailureOr<SmallVector<Type>> fields = constructorFields(location, cell);
  if (failed(fields))
    return failure();
  return destAt(location, cell.getContext(), *fields, hole);
}

//===----------------------------------------------------------------------===//
// The directives
//===----------------------------------------------------------------------===//

namespace idr {

// An init's result: what the init infers from its cell, fields and holes,
// unless another grade is written, `-> T`.
ParseResult parseCellResult(OpAsmParser &parser, Type &result, Type cell, TypeRange fields,
                            DenseI32ArrayAttr holes) {
  auto cellType = dyn_cast<CellType>(cell);
  if (!cellType)
    return parser.emitError(parser.getCurrentLocation(), "expected a cell, not ") << cell;
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(result);
  Location location = parser.getEncodedSourceLoc(parser.getCurrentLocation());
  FailureOr<SmallVector<Type>> declared = constructorFields(location, cellType);
  if (failed(declared))
    return failure();
  FailureOr<Type> inferred = initResult(location, cellType, *declared, fields, holesOf(holes));
  if (failed(inferred))
    return failure();
  result = *inferred;
  return success();
}

// An init that does not fill its constructor infers nothing, so its result
// is written.
void printCellResult(OpAsmPrinter &printer, Operation *, Type result, Type cell, TypeRange fields,
                     DenseI32ArrayAttr holes) {
  auto cellType = cast<CellType>(cell);
  FailureOr<SmallVector<Type>> declared = constructorFields(std::nullopt, cellType);
  FailureOr<Type> inferred =
      succeeded(declared) ? initResult(std::nullopt, cellType, *declared, fields, holesOf(holes))
                          : FailureOr<Type>(failure());
  if (failed(inferred) || result != *inferred)
    printer << " -> " << result;
}

// An init's destinations, one per hole, written as nothing: each is the
// destination of its hole's field.
ParseResult parseCellDests(OpAsmParser &parser, SmallVectorImpl<Type> &dests, Type cell,
                           DenseI32ArrayAttr holes) {
  auto cellType = dyn_cast<CellType>(cell);
  if (!cellType)
    return parser.emitError(parser.getCurrentLocation(), "expected a cell, not ") << cell;
  Location location = parser.getEncodedSourceLoc(parser.getCurrentLocation());
  FailureOr<SmallVector<Type>> fields = constructorFields(location, cellType);
  if (failed(fields))
    return failure();
  for (int32_t hole : holesOf(holes)) {
    FailureOr<DestType> dest = destAt(location, cellType.getContext(), *fields, hole);
    if (failed(dest))
      return failure();
    dests.push_back(*dest);
  }
  return success();
}

void printCellDests(OpAsmPrinter &, Operation *, TypeRange, Type, DenseI32ArrayAttr) {}

} // namespace idr

//===----------------------------------------------------------------------===//
// The op
//===----------------------------------------------------------------------===//

DataType CellInitOp::getDataType() { return getCell().getType().getData(); }
Tag CellInitOp::getTag() { return getCell().getType().getTag(); }

Value CellInitOp::getField(unsigned index) { return givenField(getFields(), getHoles(), index); }
Value CellInitOp::getDest(unsigned index) { return holeDest(getDests(), getHoles(), index); }

// The value its cell holds, fresh, then the destination of each hole.
LogicalResult CellInitOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                           Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  auto cell = dyn_cast<CellType>(adaptor.getCell().getType());
  if (!cell)
    return emitOptionalError(location, "writes the fields of ", adaptor.getCell().getType(),
                             ", which is no cell");
  return initTypes(location, cell, adaptor.getFields().getTypes(), adaptor.getHoles(), inferred);
}

// The value at any grade its verifier admits; the destinations exactly.
bool CellInitOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return inferred.size() == actual.size() && !inferred.empty() &&
         unrestricted(inferred.front()) == unrestricted(actual.front()) &&
         llvm::equal(inferred.drop_front(), actual.drop_front());
}

// The inferred value is counted, so it states no lifetime.
void CellInitOp::build(OpBuilder &builder, OperationState &state, Value cell, ValueRange fields,
                       ArrayRef<int32_t> holes) {
  state.addOperands(cell);
  state.addOperands(fields);
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.holes = builder.getDenseI32ArrayAttr(holes);
  properties.operandSegmentSizes = {1, static_cast<int32_t>(fields.size()), 0};
  SmallVector<Type, 2> types;
  if (failed(inferReturnTypes(state.getContext(), state.location, state.operands,
                              state.attributes.getDictionary(state.getContext()),
                              state.getRawProperties(), state.regions, types)))
    mlir::detail::reportFatalInferReturnTypesError(state);
  state.addTypes(types);
}

// A value written scoped lives in the lifetime its cell is memory of, which
// the cell's source names, so the init states that one.
void CellInitOp::build(OpBuilder &builder, OperationState &state, Type result, Value cell,
                       ValueRange fields, ArrayRef<int32_t> holes) {
  build(builder, state, cell, fields, holes);
  state.types.front() = result;
  Value lifetime = lifetimes::cellLifetime(cell);
  if (!lifetime || !freedBy(result, Release::Scoped))
    return;
  state.addOperands(lifetime);
  state.getOrAddProperties<Properties>().operandSegmentSizes[2] = 1;
}

// The value is the one result that may be scoped; the destinations take no
// hold.
Value CellInitOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void CellInitOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

// The constructor's fields in order, each a hole or the next field given,
// which fills it at the value's hold; a lifetime stated exactly for a
// scoped value; the value counted, scoped or claiming more, never static.
// The holes are ascending, so one walk reads both.
LogicalResult CellInitOp::verify() {
  Type result = getResult().getType();
  std::optional<Hold> hold = holdOf(result);
  if (!hold || hold->release() == Release::Static)
    return emitOpError("gives ") << result << ", which no count or lifetime frees";
  if (failed(lifetimes::verifyOuters(*this, 0)))
    return failure();
  bool scoped = hold->release() == Release::Scoped;
  ArrayRef<int32_t> holes = getHoles();
  if (!llvm::is_sorted(holes) || llvm::adjacent_find(holes) != holes.end())
    return emitOpError("lists its holes out of order");
  std::optional<SmallVector<Type>> fields = getDataType().determinedFields(getTag());
  if (!fields)
    return emitOpError("writes a cell whose constructor's binders its type does not determine");
  const int32_t *hole = holes.begin();
  auto given = getFields().begin();
  for (auto [index, field] : llvm::enumerate(*fields)) {
    if (hole != holes.end() && *hole == static_cast<int32_t>(index)) {
      ++hole;
      continue;
    }
    if (given == getFields().end())
      return emitOpError("is given fewer fields than its constructor has");
    if (!fillsField((*given).getType(), field, hold))
      return emitOpError("field ") << index << " has type " << (*given).getType()
                                   << ", which does not fill " << field << " of a "
                                   << (scoped ? "scoped" : "counted") << " cell";
    ++given;
  }
  if (hole != holes.end() || given != getFields().end())
    return emitOpError("is given more fields or holes than its constructor has");
  return success();
}
