// The ops of the owned stage: what their symbols must name. The hooks are
// members of the ops TableGen declares; what they check is idr.ownership's
// (OpChecks.cppm).

#include "idr/Idr.h"

import idr.ownership;

using namespace mlir;
using namespace idr;
using ownership::ctorOf;
using ownership::inOwnedStage;
using ownership::movedField;
using ownership::movesAs;

// The result is the value, owned.
LogicalResult DupOp::verify() {
  if (view(getType()) != getValue().getType())
    return emitOpError("has result ") << getType() << ", which is not " << getValue().getType()
                                      << " owned";
  return inOwnedStage(*this);
}
LogicalResult DropOp::verify() { return inOwnedStage(*this); }
LogicalResult ReuseOp::verify() { return inOwnedStage(*this); }

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
    if (Type expected = movedField(*this, field); !movesAs(value.getType(), expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  if (!isOwned(getType()))
    return emitOpError("builds a cell, which holds a reference: the result is owned");
  return success();
}

LogicalResult TakeOp::verify() { return inOwnedStage(*this); }

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
    expected.push_back(movedField(*this, fieldType(getValue().getType(), field)));
  if (expected.size() != getNumResults() ||
      !llvm::all_of(llvm::zip(getResultTypes(), expected),
                    [](auto pair) { return movesAs(std::get<0>(pair), std::get<1>(pair)); }))
    return emitOpError("has results ") << getResultTypes() << ", but " << getCtor()
                                       << " takes apart into " << TypeRange(expected);
  return success();
}
