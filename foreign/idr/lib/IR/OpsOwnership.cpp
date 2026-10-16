// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the owned stage: idr.dup, idr.drop, idr.reuse and idr.take,
// the boundary of a buffer's grade with upstream's ops, idr.own.adopt and
// idr.own.give, idr.borrow's view, and what the constructors must be: a tag
// of the value's data type, read from its body, and the types of the
// fields that move. That a program holding one is in the owned stage is
// its stage's rule, which the function verifier holds.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;
using namespace idr;

namespace {

// The type of a field that moves out of a cell, or into one: a field that
// holds references is owned.
Type movedField(Type field) { return holdsReferences(field) ? owned(field) : field; }

// Whether a value of `type` moves where `expected` is taken: the same
// type, or an exclusive value where an owned one is.
bool movesAs(Type type, Type expected) {
  return type == expected || (isOwned(expected) && isOwned(type) && view(type) == view(expected));
}

} // namespace

// The result is the value, owned: the value is the result at the
// permission it holds, a borrow or plain static data, as its type bounds.
LogicalResult DupOp::verify() {
  Type value = getValue().getType();
  if (value != atPermission(getType(), gradeOf(value).permission))
    return emitOpError("has result ") << getType() << ", which is not " << value << " owned";
  return success();
}
LogicalResult DropOp::verify() { return success(); }

DataType ReuseOp::getDataType() { return dataTypeOf(getResult().getType()); }

Value ReuseOp::getField(unsigned index) {
  return idr::detail::givenField(getFields(), getHoles(), index);
}
Value ReuseOp::getDest(unsigned index) { return idr::detail::holeDest(getDests(), getHoles(), index); }

void ReuseOp::build(OpBuilder &builder, OperationState &state, Type type, Value token,
                    Tag tag, ValueRange fields, ArrayRef<int32_t> holes) {
  const Ctor &ctor = dataTypeOf(type).getCtor(tag);
  SmallVector<Type> dests;
  for (int32_t hole : holes)
    dests.push_back(idr::detail::destOf(ctor, hole));
  build(builder, state, type, dests, token, tag, fields, holes);
}

// The fields given are the constructor's, owned where they hold
// references, the holes aside. That the cell fits is the owned stage's
// rule, which knows the take the token comes from.
LogicalResult ReuseOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getResult().getType(), getTag());
  if (failed(found))
    return failure();
  const Ctor &ctor = *found;
  if (ctor.fields.empty())
    return emitOpError("builds constructor @")
           << ctor.name.getValue() << ", which has no fields and is its atom";
  if (failed(idr::detail::verifyHoles(*this, ctor, getHoles(), getFields().size(),
                                      getDests().getTypes())))
    return failure();
  for (auto [index, field] : llvm::enumerate(ctor.fields))
    if (Value value = getField(static_cast<unsigned>(index)))
      if (Type expected = movedField(field); !movesAs(value.getType(), expected))
        return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  if (!isOwned(getResult().getType()))
    return emitOpError("builds a cell, which holds a reference: the result is owned");
  return success();
}

DataType TakeOp::getDataType() { return dataTypeOf(getValue().getType()); }

// A box's take yields its cell as a token, unless the constructor has no
// fields: that value is the constructor's atom, which is nobody's to build
// in, so the take yields nothing.
Value TakeOp::getToken() {
  return isa<BoxType>(unrestricted(getValue().getType())) && getNumResults() != 0 ? getResult(0)
                                                                                   : Value();
}

ResultRange TakeOp::getFields() { return getResults().drop_front(getToken() ? 1 : 0); }

// A token for a box with fields, then the constructor's fields, owned where
// they hold references.
LogicalResult TakeOp::verify() {
  FailureOr<std::reference_wrapper<const Ctor>> found =
      idr::detail::ctorAt(*this, getValue().getType(), getTag());
  if (failed(found))
    return failure();
  const Ctor &ctor = *found;
  SmallVector<Type> expected;
  if (isBoxed(getValue().getType()) && !ctor.fields.empty())
    expected.push_back(owned(TokenType::get(getContext())));
  // A field comes out at the value's grade times its own, as a match
  // binds it.
  for (Type field : ctor.fields)
    expected.push_back(movedField(fieldType(getValue().getType(), field)));
  if (expected.size() != getNumResults() ||
      !llvm::all_of(llvm::zip(getResultTypes(), expected),
                    [](auto pair) { return movesAs(std::get<0>(pair), std::get<1>(pair)); }))
    return emitOpError("has results ")
           << getResultTypes() << ", but constructor @" << ctor.name.getValue()
           << " takes apart into " << TypeRange(expected);
  return success();
}

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
