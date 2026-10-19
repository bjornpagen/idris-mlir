// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A constructor value and what reads it: idr.con, which builds the value,
// idr.cell.init, which writes a constructor's fields into the cell idr-rc
// gives it and the destination of each field it is built without, and
// idr.field and idr.tag. Their folds and canonicalizations are here beside
// them. Each holds a constructor's tag in its value's data type (a cell's,
// in its type), whose body says the constructor's fields, so nothing here
// reads the module or looks a constructor up by name.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether a value of `type` fills a field declared `field`: at the field's
// type, or owned at its own permission (own or excl), which moves its
// reference into the constructor. A borrow never fills a field: what a
// constructor holds, it owns.
bool fits(Type type, Type field) {
  return type == field ||
         (isOwned(type) && type == atPermission(field, gradeOf(type).permission));
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.con
//===----------------------------------------------------------------------===//

// A box's constructor allocates its cell, which idr-rc makes explicit
// (idr.cell.new and idr.cell.init), so CSE never merges two of them; an
// unused one is still dead code (wouldOpBeTriviallyDead). In the owned
// stage the constructor also takes over the references of the fields it is
// given owned, which it reports as a free of each: no pass drops or merges
// it then, since that would leave those references held where nothing
// consumes them.
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (isa<BoxType>(unrestricted(getResult().getType())))
    effects.emplace_back(MemoryEffects::Allocate::get(), getOperation()->getOpResult(0),
                         SideEffects::DefaultResource::get());
  consumedEffects(getOperation(), effects);
}

// A box is a cell: building one allocates, and reading a field of one
// loads from a cell only as large as its own constructor. A sum is its
// slots, all there whatever its constructor: building or reading it is
// computing, which may run anywhere, unless it takes an owned field over:
// hoisted out of a branch, it would take a reference on a path that never
// gave it one.
Speculation::Speculatability ConOp::getSpeculatability() {
  if (isa<BoxType>(unrestricted(getResult().getType())) ||
      llvm::any_of(getFields(), [](Value field) { return isOwned(field.getType()); }))
    return Speculation::NotSpeculatable;
  return Speculation::Speculatable;
}

DataType ConOp::getDataType() { return dataTypeOf(getResult().getType()); }

void ConOp::build(OpBuilder &builder, OperationState &state, Type type, Tag tag,
                  ValueRange fields) {
  build(builder, state, type, builder.getI32IntegerAttr(static_cast<int32_t>(tag)), fields);
}

// The parser and every builder give a tag of the type; a tag out of range
// is a hand-built op's.
FailureOr<std::reference_wrapper<const Ctor>> idr::detail::ctorAt(Operation *op, Type type,
                                                                  Tag tag) {
  DataType data = dataTypeOf(type);
  if (!data)
    return op->emitOpError("names a constructor of ") << type << ", which is no data type";
  if (static_cast<uint32_t>(tag) >= data.getCtors().size())
    return op->emitOpError("names constructor ")
           << static_cast<uint32_t>(tag) << " of \"" << data.getName() << "\", which has "
           << data.getCtors().size();
  return std::cref(data.getCtor(tag));
}

// The constructor is one of the result's type, and the fields given are
// its, each filling its field.
LogicalResult ConOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getResult().getType(), getTag());
  if (failed(found))
    return failure();
  ArrayRef<Type> fields = found->get().fields;
  if (getFields().size() != fields.size())
    return emitOpError("expects ") << fields.size() << " fields";
  for (auto [value, expected] : llvm::zip_equal(getFields(), fields))
    if (!fits(value.getType(), expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

// A constructor of constants is a constant, and a constructor rebuilt from
// the fields of a value of that constructor is the value (record eta).
OpFoldResult ConOp::fold(FoldAdaptor adaptor) {
  if (Value value = canon::eta(*this))
    return value;
  // A field folds only as a constant a constant constructor holds at its
  // type, which is no array. A poison field is the program's value where
  // control never arrives, which no constant holds: the constructor stays
  // an op around it, and idr-lower builds it.
  for (auto [field, operand] : llvm::zip_equal(adaptor.getFields(), getFields()))
    if (!field || !canon::buildable(field, operand.getType()))
      return {};
  return ConAttr::get(getContext(), getDataType(), getTag(),
                      ArrayAttr::get(getContext(), adaptor.getFields()));
}

//===----------------------------------------------------------------------===//
// idr.cell.init
//===----------------------------------------------------------------------===//

namespace {

// The constructor whose cell `cell` is, which the cell type holds in its
// box's data type.
const Ctor &ctorOf(CellType cell) { return cell.getBox().getData().getCtor(cell.getTag()); }

// The destination of hole `hole` of `cell`'s constructor: the box its field
// holds, at any grade, written through it. Failure, after an error at
// `location` when there is one, for a field the constructor does not have
// or one that is no box, which only a box's field is.
FailureOr<DestType> destOf(std::optional<Location> location, CellType cell, int32_t hole) {
  const Ctor &ctor = ctorOf(cell);
  if (hole < 0 || static_cast<size_t>(hole) >= ctor.fields.size())
    return emitOptionalError(location, "has a hole at field ", hole, ", which constructor @",
                             ctor.name.getValue(), " does not have");
  Type field = ctor.fields[static_cast<size_t>(hole)];
  auto box = dyn_cast<BoxType>(unrestricted(field));
  if (!box)
    return emitOptionalError(location, "has a hole at field ", hole, " of type ", field,
                             ", which is no box: only a box's field is written through a "
                             "destination");
  return DestType::get(box.getContext(), box);
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

// A result as an init gives it, any grade but a borrow: the box, inferred
// plain, held at the quantity Idris gave its constructor and, once
// counted, owned or exclusive; a borrow holds no reference to the cell just
// written. A destination has no grade, so it is as inferred.
bool asInferred(Type inferred, Type actual) {
  return unrestricted(inferred) == unrestricted(actual) &&
         gradeOf(inferred).permission != Permission::Borrow &&
         gradeOf(actual).permission != Permission::Borrow;
}

} // namespace

DataType CellInitOp::getDataType() { return getCell().getType().getBox().getData(); }
Tag CellInitOp::getTag() { return getCell().getType().getTag(); }

Value CellInitOp::getField(unsigned index) { return givenField(getFields(), getHoles(), index); }
Value CellInitOp::getDest(unsigned index) { return holeDest(getDests(), getHoles(), index); }

SmallVector<Type> CellInitOp::destTypes(CellType cell, ArrayRef<int32_t> holes) {
  SmallVector<Type> dests;
  for (int32_t hole : holes)
    if (FailureOr<DestType> dest = destOf(std::nullopt, cell, hole); succeeded(dest))
      dests.push_back(*dest);
  return dests;
}

// The box the cell holds, then the destination of each hole.
LogicalResult CellInitOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                           Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  auto cell = dyn_cast<CellType>(adaptor.getCell().getType());
  if (!cell)
    return emitOptionalError(location, "writes the fields of ", adaptor.getCell().getType(),
                             ", which is no cell");
  inferred.push_back(cell.getBox());
  for (int32_t hole : adaptor.getHoles()) {
    FailureOr<DestType> dest = destOf(location, cell, hole);
    if (failed(dest))
      return failure();
    inferred.push_back(*dest);
  }
  return success();
}

bool CellInitOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return llvm::equal(inferred, actual, asInferred);
}

void CellInitOp::build(OpBuilder &builder, OperationState &state, Value cell, ValueRange fields,
                       ArrayRef<int32_t> holes) {
  state.addOperands(cell);
  state.addOperands(fields);
  state.getOrAddProperties<Properties>().holes = builder.getDenseI32ArrayAttr(holes);
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

// The constructor's fields in order, each a hole or the next field given,
// which fills it; every hole and every field given used. The holes are
// ascending (Idr_HolePositions), so one walk reads both.
bool idr::detail::fillsCell(CellInitOp op) {
  ArrayRef<int32_t> holes = op.getHoles();
  OperandRange fields = op.getFields();
  const int32_t *hole = holes.begin();
  auto given = fields.begin();
  for (auto [index, field] : llvm::enumerate(ctorOf(op.getCell().getType()).fields)) {
    if (hole != holes.end() && *hole == static_cast<int32_t>(index)) {
      ++hole;
      continue;
    }
    if (given == fields.end() || !fits((*given).getType(), field))
      return false;
    ++given;
  }
  return hole == holes.end() && given == fields.end();
}

//===----------------------------------------------------------------------===//
// idr.field
//===----------------------------------------------------------------------===//

// A box is a cell: building one allocates, and reading a field of one
// loads from a cell only as large as its own constructor. A sum is its
// slots, all there whatever its constructor: building or reading it is
// computing, which may run anywhere.
Speculation::Speculatability FieldOp::getSpeculatability() {
  return isa<BoxType>(unrestricted(getValue().getType())) ? Speculation::NotSpeculatable
                                                         : Speculation::Speculatable;
}

DataType FieldOp::getDataType() { return dataTypeOf(getValue().getType()); }

void FieldOp::build(OpBuilder &builder, OperationState &state, Value value, Tag tag,
                    unsigned index) {
  Type field = dataTypeOf(value.getType()).getCtor(tag).fields[index];
  build(builder, state, fieldType(value.getType(), field), value, tag, uint64_t{index});
}

LogicalResult FieldOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getValue().getType(), getTag());
  if (failed(found))
    return failure();
  ArrayRef<Type> fields = found->get().fields;
  if (getIndex() >= fields.size())
    return emitOpError("field index out of range");
  // A field is read at the value's grade times its own, as a match binds it.
  Type expected = fieldType(getValue().getType(), fields[getIndex()]);
  if (expected != getType())
    return emitOpError("has result ") << getType() << ", but the field of a "
                                      << getValue().getType() << " is read as " << expected;
  return success();
}

// A field of a known constructor, built by idr.con or constant, also when
// it passed a linear position on the way. A linear field moves out of the
// constructor, so only the constructor's one read takes it: otherwise it
// would be used twice.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = throughLinear(getValue());
  if (!builtStateHolds(source, getOperation()))
    return {};
  if (auto con = source.getDefiningOp<ConOp>())
    if (con.getTag() == getTag()) {
      // A field read at another grade than the constructor took it is
      // the canonicalizer's, which holds it as read.
      Value field = con.getFields()[index];
      if (field.getType() == getType() &&
          (quantityOf(field.getType()) != Quantity::One || fieldReadOnce(con.getResult(), index)))
        return field;
    }
  // The constant is the operand's, as folding or constant propagation knows
  // it, or the one it passed a linear position from. Its field is read in
  // place: off a run's spine that costs nothing however long the run is,
  // where listing every field would build the rest of the run.
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  if (con && con.getTag() == getTag())
    return con.getField(index);
  return {};
}

// A field of a value whose constructor is known where it is read: a
// constant, an idr.con, or the case of an enclosing match on the same
// value, whose region argument the field is. The fold of a field of a constant is an
// attribute, and a constant is no linear value: folding shares equal
// constants, and a shared linear value would be used twice. A linear field
// of a constant is its value entered into the linear type instead, one
// entry per read, which the one use of the field then takes apart.
LogicalResult FieldOp::canonicalize(FieldOp field, PatternRewriter &rewriter) {
  Type type = field.getType();
  // A field of a known constructor read at another grade than the
  // constructor took it: the operand, held as read. A linear operand moves
  // out, so only the one read takes it.
  if (auto built = throughLinear(field.getValue()).getDefiningOp<ConOp>();
      built && built.getTag() == field.getTag()) {
    auto index = static_cast<unsigned>(field.getIndex());
    Value operand = built.getFields()[index];
    if (operand.getType() == type ||
        (quantityOf(operand.getType()) == Quantity::One && !fieldReadOnce(built.getResult(), index)))
      return failure();
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), operand, type));
    return success();
  }
  // A field read in the case of an enclosing match on the same value is
  // that region's argument: the match already took the value apart. The
  // scrutinee must be the value itself, not the value in a linear
  // position: a match that takes a linear value apart moves its fields
  // out, and a read of the value it was entered from is a second read
  // the argument cannot stand in for. A linear field moves out too, so
  // only a read that is the argument's one use takes it. The default
  // region knows no constructor.
  for (Region *region = field->getParentRegion(); region; region = region->getParentRegion()) {
    auto outer = dyn_cast<MatchOp>(region->getParentOp());
    if (!outer || outer.getScrutinee() != field.getValue())
      continue;
    std::optional<Tag> known = outer.knownTag(*region);
    if (!known)
      continue;
    if (*known != field.getTag())
      break;
    Value argument = region->front().getArgument(static_cast<unsigned>(field.getIndex()));
    if (quantityOf(type) == Quantity::One && !argument.use_empty())
      return failure();
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), argument, type));
    return success();
  }
  ConAttr con;
  if (!isLinear(type) || !matchPattern(throughLinear(field.getValue()), m_Constant(&con)) ||
      con.getTag() != field.getTag())
    return failure();
  Attribute value = con.getFields()[static_cast<unsigned>(field.getIndex())];
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  Operation *plain = dialect->materializeConstant(rewriter, value, unrestricted(type), field.getLoc());
  if (!plain)
    return failure();
  rewriter.replaceOpWithNewOp<LinEnterOp>(field, type, plain->getResult(0));
  return success();
}

//===----------------------------------------------------------------------===//
// idr.tag
//===----------------------------------------------------------------------===//

// The tag of a known constructor, built by idr.con or constant, or the one
// tag of a type of one constructor, read from the value's data type.
OpFoldResult TagOp::fold(FoldAdaptor adaptor) {
  DataType data = dataTypeOf(getValue().getType());
  if (!data)
    return {};
  Value source = throughLinear(getValue());
  std::optional<Tag> tag;
  if (auto con = source.getDefiningOp<ConOp>()) {
    tag = con.getTag();
  } else {
    auto constant = dyn_cast_or_null<ConAttr>(adaptor.getValue());
    if (constant || matchPattern(source, m_Constant(&constant)))
      tag = constant.getTag();
  }
  if (!tag && data.getCtors().size() == 1)
    tag = *data.getTags().begin();
  if (!tag)
    return {};
  return IntegerAttr::get(getType(), static_cast<int64_t>(*tag));
}

void TagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  DataType data = dataTypeOf(getValue().getType());
  size_t count = data ? data.getCtors().size() : 0;
  unsigned width = getType().getIntOrFloatBitWidth();
  setResultRange(getResult(), count == 0 ? ConstantIntRanges::maxRange(width)
                                         : idr::ranges::nonNegative(width, 0, count - 1));
}
