// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The hooks of counting's ops: the predicates their operands satisfy, the
// directives that write a known type as nothing, and each op's inferred
// results, accessors and verifier. Every op reads its constructor off a
// type refined to it and the fields off the declaration at its
// application, so nothing here reads the module or names a constructor;
// and every fact a type states (who frees a value, what it claims of its
// sharing) is read off the type, so a value typed unique meets no count
// op and no test of its sharing, and a view is never duplicated or dropped.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"

#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// What the operands ask
//===----------------------------------------------------------------------===//

namespace {

// The data type a value of `type` is, refined to the one constructor whose
// fields it determines; null for any other type.
DataType refinedData(Type type) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || !data.singleTag() || !data.determinedFields(*data.singleTag()))
    return DataType();
  return data;
}

} // namespace

namespace idr {

bool isCountedValue(Type value) { return holdsReferences(value) && freedBy(value, Release::Counted); }

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

bool isTokenValue(Type value) {
  return isa<TokenType>(unrestricted(value)) && usesOf(value) == Uses::Once;
}

bool isHeldValue(Type value) { return holdOf(value).has_value(); }

} // namespace idr

//===----------------------------------------------------------------------===//
// What a field holds
//===----------------------------------------------------------------------===//

bool idr::fillsField(Type type, Type field, std::optional<Hold> built) {
  Type carrier = unrestricted(field);
  if (unrestricted(type) != carrier && !families::refines(unrestricted(type), carrier))
    return false;
  if (usesOf(type) == Uses::Once && usesOf(field) != Uses::Once)
    return false;
  std::optional<Hold> held = holdOf(type);
  return !held || held->fits(Hold::counted()) || held->fits(Hold::staticData()) ||
         (built && built->release() == Release::Scoped);
}

LogicalResult idr::verifyRecycle(CellRecycleOp recycle, const Layouts &layouts) {
  CellType cell = recycle.getCell().getType();
  unsigned need = layouts.cells(cell.getData()).cell(cell.getTag()).size;
  auto token = cast<TokenType>(unrestricted(recycle.getToken().getType()));
  for (Type source : token.getSources()) {
    auto data = cast<DataType>(source);
    unsigned have = layouts.cells(data).cell(*data.singleTag()).size;
    if (have != need)
      return recycle.emitOpError("gives a cell of ")
             << need << " bytes from a token that may hold the " << have << "-byte cell of "
             << source;
  }
  return success();
}

//===----------------------------------------------------------------------===//
// The directives
//===----------------------------------------------------------------------===//

namespace {

// The type each field of `cell`'s constructor is filled with: the next
// field given, or, for a hole, the field's own carrier, which claims
// nothing, since what is written through the hole is not yet known.
// Failure, after an error at `location` when there is one, where the fields
// and holes do not fill the constructor's fields once each. The op may not
// have been verified yet, so the holes are read as given.
FailureOr<SmallVector<Type>> filledFields(std::optional<Location> location, CellType cell,
                                          TypeRange given, ArrayRef<int32_t> holes) {
  DataType data = cell.getData();
  std::optional<SmallVector<Type>> fields = data.determinedFields(cell.getTag());
  if (!fields)
    return emitOptionalError(location, "writes a cell of ", data,
                             ", whose constructor's binders it does not determine");
  SmallVector<Type> filled;
  auto next = given.begin();
  for (auto [index, field] : llvm::enumerate(*fields)) {
    if (llvm::is_contained(holes, static_cast<int32_t>(index)))
      filled.push_back(unrestricted(field));
    else if (next != given.end())
      filled.push_back(*next++);
    else
      return emitOptionalError(location, "is given fewer fields than its constructor has");
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
FailureOr<Type> initResult(std::optional<Location> location, CellType cell, TypeRange given,
                           ArrayRef<int32_t> holes) {
  FailureOr<SmallVector<Type>> filled = filledFields(location, cell, given, holes);
  if (failed(filled))
    return failure();
  DataType data = cell.getData();
  return graded(Grade{Uses::Once, Hold::counted(DataConOp::freshClaim(data, *filled))}, data);
}

ArrayRef<int32_t> holesOf(DenseI32ArrayAttr holes) {
  return holes ? holes.asArrayRef() : ArrayRef<int32_t>();
}

// The destination of hole `hole` of `cell`'s constructor: written through,
// once, with a value of the field's carrier. What a hole may hold is the
// destination type's own rule, asked here and stated nowhere else. Failure,
// after an error at `location` when there is one, for a field the
// constructor does not have or one no destination takes.
FailureOr<DestType> destOf(std::optional<Location> location, CellType cell, int32_t hole) {
  DataType data = cell.getData();
  std::optional<SmallVector<Type>> fields = data.determinedFields(cell.getTag());
  if (!fields)
    return emitOptionalError(location, "writes a cell of ", data,
                             ", whose constructor's binders it does not determine");
  if (hole < 0 || static_cast<size_t>(hole) >= fields->size())
    return emitOptionalError(location, "has a hole at field ", hole,
                             ", which its constructor does not have");
  MLIRContext *context = data.getContext();
  DestType dest = DestType::getChecked(location.value_or(UnknownLoc::get(context)), context,
                                       unrestricted((*fields)[static_cast<size_t>(hole)]));
  if (!dest)
    return failure();
  return dest;
}

} // namespace

namespace idr {

// A share's result: the value with its claim forgotten, unless another
// type it fits is written, `-> T`.
ParseResult parseShared(OpAsmParser &parser, Type &result, Type value) {
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(result);
  result = shared(value);
  return success();
}

void printShared(OpAsmPrinter &printer, Operation *, Type result, Type value) {
  if (result != shared(value))
    printer << " -> " << result;
}

// An init's result: what the init infers from its cell, fields and holes,
// unless another grade is written, `-> T`.
ParseResult parseCellResult(OpAsmParser &parser, Type &result, Type cell, TypeRange fields,
                            DenseI32ArrayAttr holes) {
  auto cellType = dyn_cast<CellType>(cell);
  if (!cellType)
    return parser.emitError(parser.getCurrentLocation(), "expected a cell, not ") << cell;
  if (succeeded(parser.parseOptionalArrow()))
    return parser.parseType(result);
  FailureOr<Type> inferred = initResult(parser.getEncodedSourceLoc(parser.getCurrentLocation()),
                                        cellType, fields, holesOf(holes));
  if (failed(inferred))
    return failure();
  result = *inferred;
  return success();
}

// An init that does not fill its constructor infers nothing, so its result
// is written.
void printCellResult(OpAsmPrinter &printer, Operation *, Type result, Type cell, TypeRange fields,
                     DenseI32ArrayAttr holes) {
  FailureOr<Type> inferred = initResult(std::nullopt, cast<CellType>(cell), fields, holesOf(holes));
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
  for (int32_t hole : holesOf(holes)) {
    FailureOr<DestType> dest = destOf(location, cellType, hole);
    if (failed(dest))
      return failure();
    dests.push_back(*dest);
  }
  return success();
}

void printCellDests(OpAsmPrinter &, Operation *, TypeRange, Type, DenseI32ArrayAttr) {}

} // namespace idr

//===----------------------------------------------------------------------===//
// Dup, share
//===----------------------------------------------------------------------===//

// One more reference makes the value shared: a value whose type claims its
// own cells unshared (its family's, and each in-place family's it holds)
// has none to give, and the result claims nothing.
LogicalResult CountDupOp::verify() {
  Type value = getValue().getType();
  Type result = getResult().getType();
  if (claims(value, Unique::Self))
    return emitOpError("duplicates ") << value << ", whose type claims it unshared";
  if (unrestricted(result) != unrestricted(value) || holdOf(result) != Hold::counted())
    return emitOpError("gives ") << result << ", which is not " << unrestricted(value)
                                 << " counted, claiming nothing";
  return success();
}

namespace {

// Whether a token of `from` may stand where one of `to` is asked: at the
// same uses, its hold fitting, `to` naming every cell `from` may hold.
bool widens(Type from, Type to) {
  auto a = dyn_cast<TokenType>(unrestricted(from));
  auto b = dyn_cast<TokenType>(unrestricted(to));
  if (!a || !b || usesOf(from) != usesOf(to))
    return false;
  std::optional<Hold> held = holdOf(from);
  std::optional<Hold> asked = holdOf(to);
  if (!held || !asked || !held->fits(*asked))
    return false;
  return llvm::all_of(a.getSources(),
                      [&](Type source) { return llvm::is_contained(b.getSources(), source); });
}

} // namespace

LogicalResult CountShareOp::verify() {
  Type value = getValue().getType();
  Type result = getResult().getType();
  if (!forgets(value, result) && !widens(value, result))
    return emitOpError("gives ") << value << " as " << result
                                 << ", which is no less than it claims";
  return success();
}

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
  return graded(Grade{Uses::Once, Hold::counted(holds)}, TokenType::of(data));
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
                                  TokenType::of(cast<DataType>(unrestricted(value))))};
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
// The init of a cell
//===----------------------------------------------------------------------===//

namespace {

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
  FailureOr<Type> value =
      initResult(location, cell, adaptor.getFields().getTypes(), adaptor.getHoles());
  if (failed(value))
    return failure();
  inferred.push_back(*value);
  for (int32_t hole : adaptor.getHoles()) {
    FailureOr<DestType> dest = destOf(location, cell, hole);
    if (failed(dest))
      return failure();
    inferred.push_back(*dest);
  }
  return success();
}

// The value at any grade its verifier admits; the destinations exactly.
bool CellInitOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return inferred.size() == actual.size() && !inferred.empty() &&
         unrestricted(inferred.front()) == unrestricted(actual.front()) &&
         llvm::equal(inferred.drop_front(), actual.drop_front());
}

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

void CellInitOp::build(OpBuilder &builder, OperationState &state, Type result, Value cell,
                       ValueRange fields, ArrayRef<int32_t> holes) {
  build(builder, state, cell, fields, holes);
  state.types.front() = result;
}

// The lifetime the value lives in, stated exactly when it is scoped.
Value CellInitOp::getStatedLifetime(Value made) {
  return made == getResult() ? getLifetime() : Value();
}

// A null lifetime states none, for a value no longer scoped.
void CellInitOp::setStatedLifetime(Value made, Value lifetime) {
  if (made == getResult())
    getLifetimeMutable().assign(lifetime ? ValueRange(lifetime) : ValueRange());
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
  bool scoped = hold->release() == Release::Scoped;
  if (scoped != static_cast<bool>(getLifetime()))
    return emitOpError(scoped ? "gives a scoped value but states no lifetime for it"
                              : "states a lifetime for a value that is not scoped");
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

//===----------------------------------------------------------------------===//
// Tokens
//===----------------------------------------------------------------------===//

// The null token is shared by its making: it holds no cell.
LogicalResult TokenNullOp::verify() {
  if (claims(getToken().getType(), Unique::Self))
    return emitOpError("gives a null token typed as holding its cell");
  return success();
}

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

//===----------------------------------------------------------------------===//
// Crossings into upstream's buffers
//===----------------------------------------------------------------------===//

// The store takes the plain carrier, so a value used once is never given:
// its quantity would be lost.
LogicalResult OwnGiveOp::verify() {
  Type value = getValue().getType();
  if (usesOf(value) == Uses::Once)
    return emitOpError("gives ") << value << " to memory, which would lose its one use";
  if (getResult().getType() != unrestricted(value))
    return emitOpError("gives ") << getResult().getType() << ", not the carrier of " << value;
  return success();
}
