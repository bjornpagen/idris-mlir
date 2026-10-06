// The data declaration a !idr.data or !idr.box type names.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

DataOp idr::lookupData(Operation *from, Type type) {
  FlatSymbolRefAttr name = getSumName(type);
  if (!name)
    return nullptr;
  return lookupSymbol<DataOp>(from, name.getAttr());
}
