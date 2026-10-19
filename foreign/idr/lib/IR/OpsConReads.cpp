// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What reads a constructor value: idr.field, a field of a constructor, and
// idr.tag, its tag, with their folds and canonicalizations. Each reads the
// constructor's fields from its value's data type, so nothing here reads
// the module or looks a constructor up by name.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// idr.field
//===----------------------------------------------------------------------===//

// A box is a cell: reading a field of one loads from a cell only as large
// as its own constructor. A sum is its slots, all there whatever its
// constructor: reading one is computing, which may run anywhere.
Speculation::Speculatability FieldOp::getSpeculatability() {
  return isa<BoxType>(unrestricted(getValue().getType())) ? Speculation::NotSpeculatable
                                                         : Speculation::Speculatable;
}

DataType FieldOp::getDataType() { return dataTypeOf(getValue().getType()); }

void FieldOp::build(OpBuilder &builder, OperationState &state, Value value, Tag tag,
                    unsigned index) {
  const Ctor &ctor = dataTypeOf(value.getType()).getCtor(tag);
  build(builder, state, fieldType(value.getType(), ctor.fields[index]), value, tag,
        uint64_t{index});
}

LogicalResult FieldOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getValue().getType(), getTag());
  if (failed(found))
    return failure();
  ArrayRef<Type> fields = found->get().fields;
  if (getIndex() >= fields.size())
    return emitOpError("field index out of range");
  // A field is read as a match binds it: a view of the value, a label's
  // capture of a memo cell too, which only idr.memo.run moves out.
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
