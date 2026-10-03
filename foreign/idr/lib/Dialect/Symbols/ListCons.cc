// The cons constructor of a list the string builders walk.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// The cons constructor of a list the string builders walk: `list` is a box
// of two constructors, a nil without fields and a cons of an `element` and
// the list itself; null, with an error at `op`, for any other type.
CtorOp idr::listCons(Operation *op, Type list, Type element) {
  DataOp data = lookupData(op, unrestricted(list));
  SmallVector<CtorOp> ctors = data ? data.getCtors() : SmallVector<CtorOp>{};
  if (!isa<BoxType>(unrestricted(list)) || ctors.size() != 2) {
    op->emitOpError("walks a list, a box of a nil and a cons, not ") << list;
    return nullptr;
  }
  CtorOp cons = ctors[0].getFieldTypes().size() == 2 ? ctors[0] : ctors[1];
  CtorOp nil = cons == ctors[0] ? ctors[1] : ctors[0];
  if (!nil.getFieldTypes().empty() || cons.getFieldTypes().size() != 2 ||
      cons.getFieldType(0) != element ||
      unrestricted(cons.getFieldType(1)) != unrestricted(list)) {
    op->emitOpError("walks a list of ") << element << ", not " << list;
    return nullptr;
  }
  return cons;
}
