// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops of the owned stage: idr.dup, idr.drop, idr.reuse and idr.take,
// and what their symbols must name: the constructor a symbol names and the
// types of the fields that move. That the module is in the owned stage
// needs no check of its own: each of these ops has an operand or result
// ODS declares owned, and an owned value is what puts a module there.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

using namespace mlir;
using namespace idr;

namespace {

// The constructor `ref` names, which must be one of `type`'s, or null after
// reporting why not.
CtorOp ctorOf(Operation *op, SymbolTableCollection &symbols, SymbolRefAttr ref, Type type) {
  if (ref.getNestedReferences().size() != 1) {
    op->emitOpError("expects a constructor reference @T::@C");
    return nullptr;
  }
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(
      op, FlatSymbolRefAttr::get(ref.getRootReference()));
  CtorOp ctor = lookupCtor(data, ref.getLeafReference());
  if (!ctor) {
    op->emitOpError("refers to an unknown constructor ") << ref;
    return nullptr;
  }
  if (data.getValueType() != unrestricted(type)) {
    op->emitOpError("names ") << ref << ", which is not a constructor of " << type;
    return nullptr;
  }
  return ctor;
}

// The type of a field of `ctor` that moves out of a cell, or into one: a
// field that holds references is owned. An unboxed sum's declaration comes
// from the collection the verifier holds.
Type movedField(Operation *op, SymbolTableCollection &symbols, Type field) {
  bool counted =
      holdsReferences(field, [&](Type type) { return lookupData(symbols, op, type); });
  return counted ? owned(field) : field;
}

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
LogicalResult ReuseOp::verify() { return success(); }

// The fields are the constructor's, owned where they hold references. That
// the cell fits is the owned stage's rule, which knows the take the token
// comes from.
LogicalResult ReuseOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = ctorOf(*this, symbols, getCtor(), getType());
  if (!ctor)
    return failure();
  auto types = ctor.getFieldTypes();
  if (types.empty())
    return emitOpError("builds ") << getCtor() << ", which has no fields and is its atom";
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  for (auto [field, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (Type expected = movedField(*this, symbols, field); !movesAs(value.getType(), expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  if (!isOwned(getType()))
    return emitOpError("builds a cell, which holds a reference: the result is owned");
  return success();
}

LogicalResult TakeOp::verify() { return success(); }

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
LogicalResult TakeOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = ctorOf(*this, symbols, getCtor(), getValue().getType());
  if (!ctor)
    return failure();
  SmallVector<Type> expected;
  if (isa<BoxType>(unrestricted(getValue().getType())) && !ctor.getFieldTypes().empty())
    expected.push_back(owned(TokenType::get(getContext())));
  // A field comes out at the value's grade times its own, as a match
  // binds it.
  for (Type field : ctor.getFieldTypes().getAsValueRange<TypeAttr>())
    expected.push_back(movedField(*this, symbols, fieldType(getValue().getType(), field)));
  if (expected.size() != getNumResults() ||
      !llvm::all_of(llvm::zip(getResultTypes(), expected),
                    [](auto pair) { return movesAs(std::get<0>(pair), std::get<1>(pair)); }))
    return emitOpError("has results ") << getResultTypes() << ", but " << getCtor()
                                       << " takes apart into " << TypeRange(expected);
  return success();
}
