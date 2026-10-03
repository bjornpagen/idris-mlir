// #idr.con: a constant constructor, named @T::@C.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

LogicalResult ConAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                              SymbolRefAttr ctor, ArrayAttr, Type) {
  if (ctor.getNestedReferences().size() != 1)
    return emitError() << "expects a constructor reference @T::@C, got " << ctor;
  return success();
}
