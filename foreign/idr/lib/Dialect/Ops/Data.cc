// Data declarations: idr.data and its constructors, idr.ctor.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

SmallVector<CtorOp> DataOp::getCtors() {
  return llvm::to_vector(getBody().front().getOps<CtorOp>());
}

Type DataOp::getValueType() {
  auto name = FlatSymbolRefAttr::get(getSymNameAttr());
  if (getBox())
    return BoxType::get(getContext(), name);
  return DataType::get(getContext(), name);
}

LogicalResult DataOp::verify() {
  for (Operation &op : getBody().front())
    if (!isa<CtorOp>(op))
      return op.emitOpError("is not allowed inside idr.data");
  return success();
}

Type CtorOp::getFieldType(unsigned index) {
  return cast<TypeAttr>(getFieldTypes()[index]).getValue();
}

unsigned CtorOp::getTag() {
  Block *body = (*this)->getBlock();
  return static_cast<unsigned>(std::distance(body->begin(), (*this)->getIterator()));
}

LogicalResult CtorOp::verify() {
  for (Type type : getFieldTypes().getAsValueRange<TypeAttr>())
    if (!isFieldType(type))
      return emitOpError("has a field of unsupported type ") << type;
  return success();
}
