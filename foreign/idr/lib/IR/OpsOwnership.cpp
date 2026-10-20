// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-rc writes beside idr.cell.init (OpsCon.cpp): which constructor
// has a cell (buildsCell) and the cell type, whose verifier holds it; the
// owned stage's idr.dup; the two takes of a constructor value, idr.take of
// a cell and idr.unpack of a value with none, each inferring its results
// from the value's type and the constructor; the boundary of a buffer's
// grade with upstream's ops, idr.own.adopt and idr.own.give; and
// idr.borrow's view. Which ops a program may hold is its stage's rule,
// which the program's verifier holds.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Ranges.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;
using namespace idr;

bool idr::buildsCell(Type type, Tag tag) {
  return isBoxed(type) && !dataTypeOf(type).isAtom(tag);
}

//===----------------------------------------------------------------------===//
// !idr.cell
//===----------------------------------------------------------------------===//

// `!idr.cell<!idr.box<!L>, @Cons>`: the box, then its constructor by name,
// then `frame` for a cell of the frame.
Type CellType::parse(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  BoxType box;
  IntegerAttr tag;
  if (parser.parseLess() || parser.parseType(box) || parser.parseComma() ||
      parseCtorRef(parser, box, tag))
    return {};
  Lifetime lifetime = Lifetime::Heap;
  if (succeeded(parser.parseOptionalComma())) {
    if (parser.parseKeyword(stringifyLifetime(Lifetime::Frame)))
      return {};
    lifetime = Lifetime::Frame;
  }
  if (parser.parseGreater())
    return {};
  return getChecked([&] { return parser.emitError(loc); }, parser.getContext(), box,
                    Tag{static_cast<uint32_t>(tag.getInt())}, lifetime);
}

void CellType::print(AsmPrinter &printer) const {
  printer << '<';
  printer.printType(getBox());
  printer << ", ";
  printer.printSymbolName(getBox().getData().getCtor(getTag()).name.getValue());
  if (getLifetime() != Lifetime::Heap)
    printer << ", " << stringifyLifetime(getLifetime());
  printer << '>';
}

// A cell is of a constructor of its box's data type that has one: an atom
// has none.
LogicalResult CellType::verify(function_ref<InFlightDiagnostic()> emitError, BoxType box,
                               Tag tag, Lifetime) {
  DataType data = box.getData();
  if (static_cast<uint32_t>(tag) >= data.getCtors().size())
    return emitError() << "names constructor " << static_cast<uint32_t>(tag) << " of \""
                       << data.getName() << "\", which has " << data.getCtors().size();
  if (!buildsCell(box, tag))
    return emitError() << "is a cell of @" << data.getCtor(tag).name.getValue() << ", an atom of \""
                       << data.getName() << "\", which has no cell";
  return success();
}

// A cell is memory whose fields are not written yet: it holds no reference
// until idr.cell.init writes them, and that init is its one use, which its
// type alone says. Its source wrote its header, so it is one pointer, never
// null, to a cell that starts with it.
bool CellType::holdsReferences() const { return false; }
bool CellType::holdsWorld() const { return false; }
bool CellType::isLinearByType() const { return true; }
bool CellType::isCounted() const { return false; }
bool CellType::isCellPointer() const { return true; }

//===----------------------------------------------------------------------===//
// idr.dup
//===----------------------------------------------------------------------===//

// The result is the value, owned: the value, lent at the heap if it is
// static, is the result at the permission it holds, a borrow or plain
// static data, as its type bounds. An owned value lives on the heap.
LogicalResult DupOp::verify() {
  Type value = getValue().getType();
  if (lent(value) != atPermission(getType(), gradeOf(value).permission))
    return emitOpError("has result ") << getType() << ", which is not " << value << " owned";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.take and idr.unpack
//===----------------------------------------------------------------------===//

namespace {

// The constructor `tag` of a value of `type`, which a take or an unpack
// takes apart, or failure after an error at `location`.
FailureOr<std::reference_wrapper<const Ctor>> takenApart(std::optional<Location> location,
                                                         Type type, Tag tag) {
  DataType data = dataTypeOf(type);
  if (!data)
    return emitOptionalError(location, "takes apart ", type, ", which is no constructor value");
  if (static_cast<uint32_t>(tag) >= data.getCtors().size())
    return emitOptionalError(location, "takes apart constructor ", static_cast<uint32_t>(tag),
                             " of \"", data.getName(), "\", which has ", data.getCtors().size());
  return std::cref(data.getCtor(tag));
}

// The fields of `ctor` taken apart from a value of `type`: each read at the
// value's grade times its own, as a match binds it, and owned where it
// holds references, which move out with it.
void appendFields(Type type, const Ctor &ctor, SmallVectorImpl<Type> &results) {
  for (Type field : ctor.fields) {
    Type read = fieldType(type, field);
    results.push_back(holdsReferences(read) ? owned(read) : read);
  }
}

// A result inferred owned may be held exclusive, the grade idr-rc's commit
// writes where it proves one; any other is as inferred.
bool ownedAlike(Type inferred, Type actual) {
  return inferred == actual ||
         (isOwned(inferred) && isOwned(actual) && view(inferred) == view(actual));
}

// The result types `state` infers, added to it as ODS's own inferring
// builders add them: a builder given a value it cannot infer from is a bug
// of its caller's.
template <typename Op>
void addInferredTypes(OperationState &state) {
  SmallVector<Type, 4> types;
  if (failed(Op::inferReturnTypes(state.getContext(), state.location, state.operands,
                                  state.attributes.getDictionary(state.getContext()),
                                  state.getRawProperties(), state.regions, types)))
    mlir::detail::reportFatalInferReturnTypesError(state);
  state.addTypes(types);
}

} // namespace

DataType TakeOp::getDataType() { return dataTypeOf(getValue().getType()); }
DataType UnpackOp::getDataType() { return dataTypeOf(getValue().getType()); }

// The take of a cell: its token, then its constructor's fields.
LogicalResult TakeOp::inferReturnTypes(MLIRContext *context, std::optional<Location> location,
                                       Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type type = adaptor.getValue().getType();
  Tag tag = adaptor.getTag();
  FailureOr<std::reference_wrapper<const Ctor>> ctor = takenApart(location, type, tag);
  if (failed(ctor))
    return failure();
  if (!buildsCell(type, tag))
    return emitOptionalError(location, "takes the cell of constructor @",
                             ctor->get().name.getValue(), " of ", type,
                             ", which has none: idr.unpack takes it apart");
  inferred.push_back(owned(idr::TokenType::get(context)));
  appendFields(type, *ctor, inferred);
  return success();
}

// The take of a value with no cell of its own: its constructor's fields,
// an unboxed sum's slots, or nothing for an atom.
LogicalResult UnpackOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                         Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type type = adaptor.getValue().getType();
  Tag tag = adaptor.getTag();
  FailureOr<std::reference_wrapper<const Ctor>> ctor = takenApart(location, type, tag);
  if (failed(ctor))
    return failure();
  if (buildsCell(type, tag))
    return emitOptionalError(location, "unpacks constructor @", ctor->get().name.getValue(),
                             " of ", type, ", which has a cell: idr.take takes it apart");
  appendFields(type, *ctor, inferred);
  return success();
}

bool TakeOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return llvm::equal(inferred, actual, ownedAlike);
}

bool UnpackOp::isCompatibleReturnTypes(TypeRange inferred, TypeRange actual) {
  return llvm::equal(inferred, actual, ownedAlike);
}

void TakeOp::build(OpBuilder &builder, OperationState &state, Value value, Tag tag) {
  state.addOperands(value);
  state.getOrAddProperties<Properties>().tag = builder.getI32IntegerAttr(static_cast<int32_t>(tag));
  addInferredTypes<TakeOp>(state);
}

void UnpackOp::build(OpBuilder &builder, OperationState &state, Value value, Tag tag) {
  state.addOperands(value);
  state.getOrAddProperties<Properties>().tag = builder.getI32IntegerAttr(static_cast<int32_t>(tag));
  addInferredTypes<UnpackOp>(state);
}

//===----------------------------------------------------------------------===//
// A buffer's grade at upstream's ops
//===----------------------------------------------------------------------===//

// The buffer is the result of the memref.alloc whose reference this takes
// over, and this is its one use.
LogicalResult OwnAdoptOp::verify() {
  auto alloc = getMemref().getDefiningOp<memref::AllocOp>();
  if (!alloc || !getMemref().hasOneUse())
    return emitOpError("takes over the reference of a buffer that is no memref.alloc's result "
                       "of one use");
  return success();
}

// The one use is the value a memref.store writes into a buffer whose
// elements hold references.
LogicalResult OwnGiveOp::verify() {
  if (!getResult().hasOneUse())
    return emitOpError("hands its reference to more than one use");
  auto store = dyn_cast<memref::StoreOp>(*getResult().user_begin());
  if (!store || store.getValueToStore() != getResult() ||
      store.getMemRefType().getElementType() != getResult().getType() ||
      !holdsReferences(getResult().getType()))
    return emitOpError("hands its reference to no memref.store of a counted element");
  return success();
}

void OwnGiveOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  consumedEffects(getOperation(), effects);
}

// A view is a view of the owned value it borrows.
Value BorrowOp::getViewSource() { return getValue(); }

// Each op that only changes its operand's grade gives its operand's range
// (Idr_ResultCarriesOperand).
void BorrowOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                             SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}

void ShareOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                            SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}

void LinEnterOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                               SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}

void LinUseOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                             SetIntLatticeFn setResultRange) {
  ranges::carried(getResult(), ranges.front(), setResultRange);
}
