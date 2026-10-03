// idr.ownership:opchecks: what the hooks of the owned stage's ops check:
// the constructor a symbol names, the types of the fields that move, and
// the stage the module is in. The hooks themselves are members of the ops
// TableGen declares, so they stay plain units (Ops.cc) that call these.
export module idr.ownership:opchecks;

import idr.mlir;
import idr.dialect;

import :counting;
import :stage;

using namespace mlir;

export namespace idr::ownership {

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
// field that holds references is owned.
Type movedField(Operation *op, Type field) {
  Counting counting(op->getParentOfType<ModuleOp>());
  return counting.counted(field) ? owned(field) : field;
}

// Whether a value of `type` moves where `expected` is taken: the same
// type, or an exclusive value where an owned one is.
bool movesAs(Type type, Type expected) {
  return type == expected || (isOwned(expected) && isOwned(type) && view(type) == view(expected));
}

// Whether `op` is in a module in the owned stage, or failure after
// reporting that it counts references, which only such a module does.
LogicalResult inOwnedStage(Operation *op) {
  auto module = op->getParentOfType<ModuleOp>();
  auto stage = module ? module->getAttrOfType<StringAttr>(stageAttr) : StringAttr();
  if (!stage || stage.getValue() != ownedStage)
    return op->emitOpError("counts references, which only a module in the owned stage "
                           "(idr.stage = \"owned\") does");
  return success();
}

} // namespace idr::ownership
