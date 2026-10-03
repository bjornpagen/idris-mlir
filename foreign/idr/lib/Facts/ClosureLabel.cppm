// idr.facts:closurelabel: the label a constructor of a sum of closures
// names.
export module idr.facts:closurelabel;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::facts {

// The label that `ctor` names when it builds a closure: a constructor of a
// sum of closures (an `idr.data ... closures`), named after its label's
// function. Null for any other constructor.
StringAttr closureLabel(Operation *from, SymbolRefAttr ctor) {
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(
      from, FlatSymbolRefAttr::get(ctor.getRootReference()));
  return data && data.getClosures() ? ctor.getLeafReference() : StringAttr();
}

} // namespace idr::facts
