// The label a constructor of a sum of closures names.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

StringAttr facts::closureLabel(Operation *from, SymbolRefAttr ctor) {
  auto data = SymbolTable::lookupNearestSymbolFrom<DataOp>(
      from, FlatSymbolRefAttr::get(ctor.getRootReference()));
  return data && data.getClosures() ? ctor.getLeafReference() : StringAttr();
}
