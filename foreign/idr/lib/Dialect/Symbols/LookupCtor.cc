// A constructor, by its name in its data declaration or by `@T::@C`.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

CtorOp idr::lookupCtor(DataOp data, StringRef ctor) {
  if (!data)
    return nullptr;
  return dyn_cast_or_null<CtorOp>(SymbolTable::lookupSymbolIn(data, ctor));
}

CtorOp idr::lookupCtor(Operation *from, SymbolRefAttr ctor) {
  if (ctor.getNestedReferences().size() != 1)
    return nullptr;
  return lookupCtor(lookupSymbol<DataOp>(from, ctor.getRootReference()),
                    ctor.getLeafReference());
}
