// The ops of the owned stage: what their symbols must name.

#include "Ownership/Ownership.h"

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
  if (data.getValueType() != type) {
    op->emitOpError("names ") << ref << ", which is not a constructor of " << type;
    return nullptr;
  }
  return ctor;
}

LogicalResult inOwnedStage(Operation *op) {
  auto module = op->getParentOfType<ModuleOp>();
  auto stage = module ? module->getAttrOfType<StringAttr>(ownership::stageAttr) : StringAttr();
  if (!stage || stage.getValue() != ownership::ownedStage)
    return op->emitOpError("counts references, which only a module in the owned stage "
                           "(idr.stage = \"owned\") does");
  return success();
}

} // namespace

LogicalResult IncOp::verify() { return inOwnedStage(*this); }
LogicalResult DecOp::verify() { return inOwnedStage(*this); }
LogicalResult ReuseOp::verify() { return inOwnedStage(*this); }

// The fields are the constructor's, as idr.con's. That the cell fits is the
// owned stage's rule, which knows the take the token comes from.
LogicalResult ReuseOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = ctorOf(*this, symbols, getCtor(), getType());
  if (!ctor)
    return failure();
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  for (auto [expected, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (expected != value.getType())
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}

LogicalResult TakeOp::verify() { return inOwnedStage(*this); }

Value TakeOp::getToken() {
  return isa<BoxType>(getValue().getType()) ? getResult(0) : Value();
}

ResultRange TakeOp::getFields() {
  return getResults().drop_front(isa<BoxType>(getValue().getType()) ? 1 : 0);
}

// A token for a box, then the constructor's fields.
LogicalResult TakeOp::verifySymbolUses(SymbolTableCollection &symbols) {
  CtorOp ctor = ctorOf(*this, symbols, getCtor(), getValue().getType());
  if (!ctor)
    return failure();
  SmallVector<Type> expected;
  if (isa<BoxType>(getValue().getType()))
    expected.push_back(TokenType::get(getContext()));
  llvm::append_range(expected, ctor.getFieldTypes().getAsValueRange<TypeAttr>());
  if (!llvm::equal(expected, getResultTypes()))
    return emitOpError("has results ") << getResultTypes() << ", but " << getCtor()
                                       << " takes apart into " << TypeRange(expected);
  return success();
}
