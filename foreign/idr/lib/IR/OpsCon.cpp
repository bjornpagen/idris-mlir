// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A constructor value and what reads it: idr.con, which allocates a box's
// cell and gives the destination of each field it is built without,
// idr.field and idr.tag. Their folds and canonicalizations are here beside
// them. Each holds a constructor's tag in its value's data type, whose body
// says the constructor's fields, so nothing here reads the module or looks
// a constructor up by name.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// idr.con
//===----------------------------------------------------------------------===//

// A box's constructor allocates its cell, so CSE never merges two of them;
// an unused one is still dead code (wouldOpBeTriviallyDead). A cell
// idr-stack keeps in its frame (`stack`) is stack memory, the resource
// MLIR's allocas use. In the owned stage the constructor also takes over
// the references of the fields it is given owned, which it reports as a
// free of each: no pass drops or merges it then, since that would leave
// those references held where nothing consumes them.
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (isa<BoxType>(unrestricted(getResult().getType()))) {
    SideEffects::Resource *memory = getStack()
                                        ? static_cast<SideEffects::Resource *>(
                                              SideEffects::AutomaticAllocationScopeResource::get())
                                        : SideEffects::DefaultResource::get();
    effects.emplace_back(MemoryEffects::Allocate::get(), getOperation()->getOpResult(0), memory);
  }
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

// The type of the destination of field `index` of `ctor`: the field's word,
// whatever grade the field is held at.
Type idr::detail::destOf(const Ctor &ctor, int32_t index) {
  Type field = ctor.fields[static_cast<size_t>(index)];
  return DestType::get(field.getContext(), unrestricted(field));
}

Value idr::detail::givenField(ValueRange fields, ArrayRef<int32_t> holes, unsigned index) {
  const int32_t *hole = llvm::lower_bound(holes, static_cast<int32_t>(index));
  if (hole != holes.end() && *hole == static_cast<int32_t>(index))
    return Value();
  return fields[index - static_cast<unsigned>(hole - holes.begin())];
}

Value idr::detail::holeDest(ResultRange dests, ArrayRef<int32_t> holes, unsigned index) {
  const int32_t *hole = llvm::lower_bound(holes, static_cast<int32_t>(index));
  if (hole == holes.end() || *hole != static_cast<int32_t>(index))
    return Value();
  return dests[static_cast<unsigned>(hole - holes.begin())];
}

Value ConOp::getField(unsigned index) {
  return idr::detail::givenField(getFields(), getHoles(), index);
}
Value ConOp::getDest(unsigned index) { return idr::detail::holeDest(getDests(), getHoles(), index); }

void ConOp::build(OpBuilder &builder, OperationState &state, Type type, Tag tag,
                  ValueRange fields, ArrayRef<int32_t> holes, bool stack) {
  const Ctor &ctor = dataTypeOf(type).getCtor(tag);
  SmallVector<Type> dests;
  for (int32_t hole : holes)
    dests.push_back(idr::detail::destOf(ctor, hole));
  build(builder, state, type, dests, tag, fields, holes, stack);
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

// The holes are distinct fields of `ctor`, ascending, of a box's cell, and
// the rest of its fields are given; each destination is the word of its
// hole.
LogicalResult idr::detail::verifyHoles(Operation *op, const Ctor &ctor, ArrayRef<int32_t> holes,
                                       size_t fields, TypeRange dests) {
  if (!holes.empty() && !isBoxed(op->getResult(0).getType()))
    return op->emitOpError("has holes, which only a box's cell has");
  for (auto [i, hole] : llvm::enumerate(holes))
    if (hole < 0 || static_cast<size_t>(hole) >= ctor.fields.size() ||
        (i > 0 && holes[i - 1] >= hole))
      return op->emitOpError("expects its holes to be distinct fields, ascending");
  if (fields + holes.size() != ctor.fields.size())
    return op->emitOpError("expects ") << ctor.fields.size() - holes.size() << " fields";
  if (dests.size() != holes.size())
    return op->emitOpError("expects a destination per hole");
  for (auto [hole, dest] : llvm::zip_equal(holes, dests))
    if (dest != destOf(ctor, hole))
      return op->emitOpError("gives ") << dest << " for field " << hole << ", whose destination is "
                                       << destOf(ctor, hole);
  return success();
}

// The constructor is one of the result's type, and the fields given are
// its, the holes aside: in the owned stage a field that holds references
// is owned (or exclusive), the field's type at the value's permission, and
// moves into the cell. A borrow never fills a field: what a cell holds, it
// owns. A cell idr-stack keeps in its frame is a box's.
LogicalResult ConOp::verify() {
  if (getStack() && !isa<BoxType>(unrestricted(getResult().getType())))
    return emitOpError("is kept on the stack, which only a box's cell is");
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getResult().getType(), getTag());
  if (failed(found))
    return failure();
  const Ctor &ctor = *found;
  if (failed(idr::detail::verifyHoles(*this, ctor, getHoles(), getFields().size(),
                                      getDests().getTypes())))
    return failure();
  for (auto [index, expected] : llvm::enumerate(ctor.fields)) {
    Value value = getField(static_cast<unsigned>(index));
    if (value && value.getType() != expected &&
        !(isOwned(value.getType()) &&
          value.getType() == atPermission(expected, gradeOf(value.getType()).permission)))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  }
  return success();
}

// A constructor of constants is a constant, and a constructor rebuilt from
// the fields of a value of that constructor is the value (record eta). One
// with a hole is neither: the hole has no value until it is written.
LogicalResult ConOp::fold(FoldAdaptor adaptor, SmallVectorImpl<OpFoldResult> &results) {
  if (!getHoles().empty())
    return failure();
  if (Value value = canon::eta(*this)) {
    results.push_back(value);
    return success();
  }
  // A field folds only as a constant a constant constructor holds at its
  // type, which is no array. A poison field is the program's value where
  // control never arrives, which no constant holds: the constructor stays
  // an op around it, and idr-lower builds it.
  for (auto [field, operand] : llvm::zip_equal(adaptor.getFields(), getFields()))
    if (!field || !canon::buildable(field, operand.getType()))
      return failure();
  results.push_back(ConAttr::get(getContext(), getDataType(), getTag(),
                                 ArrayAttr::get(getContext(), adaptor.getFields())));
  return success();
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
// would be used twice. A hole of the constructor has no value until its
// destination is written, so a read of it stays a read of the cell.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    if (con.getTag() == getTag()) {
      // A field read at another grade than the constructor took it is
      // the canonicalizer's, which holds it as read.
      Value field = con.getField(index);
      if (field && field.getType() == getType() &&
          (quantityOf(field.getType()) != Quantity::One || fieldReadOnce(con.getResult(), index)))
        return field;
    }
  // The constant is the operand's, as folding or constant propagation knows
  // it, or the one it passed a linear position from.
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  if (con && con.getTag() == getTag()) {
    // One field of the first cell, read in place: off a run's spine that
    // costs nothing however long the run is, where listing every field
    // would build the rest of the run. A run's cells hold all the fields
    // but the spine.
    size_t count = con.getCells().front().size() + (con.isRun() ? 1u : 0u);
    if (index < count)
      return con.getField(index);
  }
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
  // out, so only the one read takes it; a hole is no value yet, and is
  // never read.
  if (auto built = throughLinear(field.getValue()).getDefiningOp<ConOp>();
      built && built.getTag() == field.getTag()) {
    auto index = static_cast<unsigned>(field.getIndex());
    Value operand = built.getField(index);
    if (!operand || operand.getType() == type ||
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
  // only a read that is the argument's one use takes it.
  for (Region *region = field->getParentRegion(); region; region = region->getParentRegion()) {
    auto outer = dyn_cast<MatchOp>(region->getParentOp());
    if (!outer || outer.getScrutinee() != field.getValue())
      continue;
    unsigned index = region->getRegionNumber();
    if (index >= outer.getCases().size())
      continue;
    if (outer.getCaseTag(index) != field.getTag())
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
