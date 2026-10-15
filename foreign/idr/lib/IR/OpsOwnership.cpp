// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the owned stage: idr.dup, idr.drop, idr.reuse and idr.take,
// the boundary of a buffer's grade with upstream's ops, idr.own.adopt and
// idr.own.give, and what the constructors must be: one of the value's data type, read
// from its body, and the types of the fields that move. That the module is
// in the owned stage needs no check of its own: each of these ops has an
// operand or result ODS declares owned, and an owned value is what puts a
// module there.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"

using namespace mlir;
using namespace idr;

namespace {

// The constructor `ref` names, which must be one of `type`'s data type's,
// or null after reporting why not.
const Ctor *ctorOf(Operation *op, FlatSymbolRefAttr ref, Type type) {
  DataType data = dataTypeOf(type);
  if (!data || !data.hasBody()) {
    op->emitOpError("names a constructor of ") << type << ", which has no body";
    return nullptr;
  }
  std::optional<unsigned> tag = data.getTag(ref.getValue());
  if (!tag) {
    op->emitOpError("names ") << ref << ", which is not a constructor of " << type;
    return nullptr;
  }
  return &data.getCtor(*tag);
}

// The type of a field that moves out of a cell, or into one: a field that
// holds references is owned.
Type movedField(Type field) { return holdsReferences(field) ? owned(field) : field; }

// Whether a value of `type` moves where `expected` is taken: the same
// type, or an exclusive value where an owned one is.
bool movesAs(Type type, Type expected) {
  return type == expected || (isOwned(expected) && isOwned(type) && view(type) == view(expected));
}

} // namespace

// The result is the value, owned.
LogicalResult DupOp::verify() {
  if (view(getType()) != getValue().getType())
    return emitOpError("has result ") << getType() << ", which is not " << getValue().getType()
                                      << " owned";
  return success();
}
LogicalResult DropOp::verify() { return success(); }

DataType ReuseOp::getDataType() { return dataTypeOf(getType()); }
unsigned ReuseOp::getTag() { return *getDataType().getTag(getCtor()); }

// The fields are the constructor's, owned where they hold references. That
// the cell fits is the owned stage's rule, which knows the take the token
// comes from.
LogicalResult ReuseOp::verify() {
  const Ctor *ctor = ctorOf(*this, getCtorAttr(), getType());
  if (!ctor)
    return failure();
  if (ctor->fields.empty())
    return emitOpError("builds ") << getCtorAttr() << ", which has no fields and is its atom";
  if (ctor->fields.size() != getFields().size())
    return emitOpError("expects ") << ctor->fields.size() << " fields";
  for (auto [field, value] : llvm::zip(ctor->fields, getFields()))
    if (Type expected = movedField(field); !movesAs(value.getType(), expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  if (!isOwned(getType()))
    return emitOpError("builds a cell, which holds a reference: the result is owned");
  return success();
}

DataType TakeOp::getDataType() { return dataTypeOf(getValue().getType()); }
unsigned TakeOp::getTag() { return *getDataType().getTag(getCtor()); }

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
  const Ctor *ctor = ctorOf(*this, getCtorAttr(), getValue().getType());
  if (!ctor)
    return failure();
  SmallVector<Type> expected;
  if (isBoxed(getValue().getType()) && !ctor->fields.empty())
    expected.push_back(owned(TokenType::get(getContext())));
  // A field comes out at the value's grade times its own, as a match
  // binds it.
  for (Type field : ctor->fields)
    expected.push_back(movedField(fieldType(getValue().getType(), field)));
  if (expected.size() != getNumResults() ||
      !llvm::all_of(llvm::zip(getResultTypes(), expected),
                    [](auto pair) { return movesAs(std::get<0>(pair), std::get<1>(pair)); }))
    return emitOpError("has results ") << getResultTypes() << ", but " << getCtorAttr()
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
