// idr.dest.of: the destination of a field a cell was built without.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

LogicalResult DestOfOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data =
      symbols.lookupNearestSymbolFrom<DataOp>(*this, getSumName(getValue().getType()));
  CtorOp ctor = lookupCtor(data, getCtor());
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
