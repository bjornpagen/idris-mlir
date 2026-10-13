// A constructor value and what reads it: idr.con, which allocates a box's
// cell, idr.field, idr.tag and idr.dest.of, the destination of a field a
// cell was built without. Their folds and canonicalizations are here
// beside them. A tag's folder and ranges run with no table in hand, so
// each reads the value's declaration with one scan of the module's top
// level per call.

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
// idr-stack keeps in its frame (`idr.stack`) is stack memory, the resource
// MLIR's allocas use. In the owned stage the constructor also takes over
// the references of the fields it is given owned, which it reports as a
// free of each: no pass drops or merges it then, since that would leave
// those references held where nothing consumes them.
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (isa<BoxType>(unrestricted(getType()))) {
    auto *dialect = static_cast<IdrDialect *>((*this)->getDialect());
    SideEffects::DefaultResource *memory =
        dialect->getStackAttrHelper().isAttrPresent(*this)
            ? SideEffects::AutomaticAllocationScopeResource::get()
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
  if (isa<BoxType>(unrestricted(getType())) ||
      llvm::any_of(getFields(), [](Value field) { return isOwned(field.getType()); }))
    return Speculation::NotSpeculatable;
  return Speculation::Speculatable;
}

LogicalResult ConOp::verifySymbolUses(SymbolTableCollection &symbols) {
  SymbolRefAttr ref = getCtor();
  if (ref.getNestedReferences().size() != 1)
    return emitOpError("expects a constructor reference @T::@C");
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(
      *this, FlatSymbolRefAttr::get(ref.getRootReference()));
  CtorOp ctor = lookupCtor(data, ref.getLeafReference());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << ref;
  if (data.getValueType() != unrestricted(getType()))
    return emitOpError("builds ") << ref << " but has type " << getType();
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  // In the owned stage a field that holds references is owned (or
  // exclusive): it moves into the cell.
  for (auto [expected, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (expected != value.getType() && !(isOwned(value.getType()) && view(value.getType()) == expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

// A constructor of constants is a constant, and a constructor rebuilt from
// the fields of a value of that constructor is the value (record eta).
OpFoldResult ConOp::fold(FoldAdaptor adaptor) {
  if (Value value = canon::eta(*this))
    return value;
  // A field folds only as a constant the dialect builds at its type. A
  // poison field is the program's value where control never arrives, which
  // no constant holds: the constructor stays an op around it, and idr-lower
  // builds it.
  for (auto [field, operand] : llvm::zip_equal(adaptor.getFields(), getFields()))
    if (!field || !canon::buildable(field, operand.getType()))
      return {};
  return ConAttr::get(getContext(), getCtor(), ArrayAttr::get(getContext(), adaptor.getFields()));
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

LogicalResult FieldOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = lookupCtor(lookupData(symbols, *this, getValue().getType()), getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  // A field is read at the value's grade times its own, as a match binds it.
  Type expected = fieldType(getValue().getType(), ctor.getFieldType(static_cast<unsigned>(getIndex())));
  if (expected != getType())
    return emitOpError("has result ") << getType() << ", but the field of a "
                                      << getValue().getType() << " is read as " << expected;
  return success();
}

// A field of a known constructor, built by idr.con or constant, also when
// it passed a linear position on the way. A linear field moves out of the
// constructor, so only the constructor's one read takes it: otherwise it
// would be used twice. A field the constructor was built without
// (idr.dest.pending) has no value until its destination is written, so a
// read of it is not the pending operand: it stays a read of the cell.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    if (con.getCtor().getLeafReference() == getCtorAttr().getAttr()) {
      // A field read at another grade than the constructor took it is
      // the canonicalizer's, which holds it as read.
      Value field = con.getFields()[index];
      if (!field.getDefiningOp<PendingOp>() && field.getType() == getType() &&
          (quantityOf(field.getType()) != Quantity::One || fieldReadOnce(con.getResult(), index)))
        return field;
    }
  // The constant is the operand's, as folding or constant propagation knows
  // it, or the one it passed a linear position from.
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  if (con && con.getCtor().getLeafReference() == getCtorAttr().getAttr()) {
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
  // out, so only the one read takes it; a pending operand (a field the
  // constructor was built without) is no value yet, and is never read.
  if (auto built = throughLinear(field.getValue()).getDefiningOp<ConOp>();
      built && built.getCtor().getLeafReference() == field.getCtorAttr().getAttr()) {
    auto index = static_cast<unsigned>(field.getIndex());
    Value operand = built.getFields()[index];
    if (operand.getDefiningOp<PendingOp>() || operand.getType() == type ||
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
    if (cast<FlatSymbolRefAttr>(outer.getCases()[index]).getAttr() != field.getCtorAttr().getAttr())
      break;
    Value argument = region->front().getArgument(static_cast<unsigned>(field.getIndex()));
    if (quantityOf(type) == Quantity::One && !argument.use_empty())
      return failure();
    rewriter.replaceOp(field, heldAs(rewriter, field.getLoc(), argument, type));
    return success();
  }
  ConAttr con;
  if (!isLinear(type) || !matchPattern(throughLinear(field.getValue()), m_Constant(&con)) ||
      con.getCtor().getLeafReference() != field.getCtorAttr().getAttr())
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

// The tag of a known constructor, built by idr.con or constant, or 0 for a
// type of one constructor. The declaration is read once, and the
// constructor found within it.
OpFoldResult TagOp::fold(FoldAdaptor adaptor) {
  Value source = throughLinear(getValue());
  SymbolRefAttr known;
  if (auto con = source.getDefiningOp<ConOp>()) {
    known = con.getCtor();
  } else {
    auto constant = dyn_cast_or_null<ConAttr>(adaptor.getValue());
    if (constant || matchPattern(source, m_Constant(&constant)))
      known = constant.getCtor();
  }
  DataOp data = declarationOf(*this, getValue().getType());
  if (!data)
    return {};
  CtorOp ctor;
  if (known) {
    ctor = lookupCtor(data, known.getLeafReference());
  } else {
    auto ctors = data.getBody().front().getOps<CtorOp>();
    if (!ctors.empty() && std::next(ctors.begin()) == ctors.end())
      ctor = *ctors.begin();
  }
  if (!ctor)
    return {};
  return IntegerAttr::get(getType(), static_cast<int64_t>(ctor.getTag()));
}

void TagOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  DataOp data = declarationOf(*this, getValue().getType());
  size_t count = data ? llvm::range_size(data.getBody().front().getOps<CtorOp>()) : 0;
  unsigned width = getType().getIntOrFloatBitWidth();
  setResultRange(getResult(), count == 0 ? ConstantIntRanges::maxRange(width)
                                         : idr::ranges::nonNegative(width, 0, count - 1));
}

//===----------------------------------------------------------------------===//
// idr.dest.of
//===----------------------------------------------------------------------===//

LogicalResult DestOfOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = lookupCtor(lookupData(symbols, *this, getValue().getType()), getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  // A destination is the field's word, whatever grade the field is held at.
  if (unrestricted(ctor.getFieldType(static_cast<unsigned>(getIndex()))) != getType().getValue())
    return emitOpError("destination type does not match the field type");
  return success();
}

// The cell was built here, by an idr.con or idr.reuse of the constructor,
// with the field pending: a destination names a field that has no value
// yet, and nothing else does. In the owned stage the cell is owned and
// the destination reads it through a view.
LogicalResult DestOfOp::verify() {
  Value cell = getValue();
  if (auto borrow = cell.getDefiningOp<BorrowOp>())
    cell = borrow.getValue();
  Operation *made = cell.getDefiningOp();
  ValueRange fields;
  SymbolRefAttr ctor;
  if (auto con = dyn_cast_or_null<ConOp>(made)) {
    fields = con.getFields();
    ctor = con.getCtor();
  } else if (auto reuse = dyn_cast_or_null<ReuseOp>(made)) {
    fields = reuse.getFields();
    ctor = reuse.getCtor();
  } else {
    return emitOpError("expects the cell of an idr.con or idr.reuse");
  }
  auto index = static_cast<unsigned>(getIndex());
  if (ctor.getLeafReference() != getCtorAttr().getAttr())
    return emitOpError("names a field of ") << getCtorAttr() << ", which did not build the cell";
  if (index >= fields.size() || !fields[index].getDefiningOp<PendingOp>())
    return emitOpError("names a field the cell was built with");
  return success();
}
