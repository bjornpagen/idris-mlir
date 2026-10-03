// !idr.dest: one word of a cell that a box's reference fills.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// A destination is one word of a cell that a box's reference fills: a
// field of box type.
LogicalResult DestType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (!isa<BoxType>(value))
    return emitError() << "expects !idr.dest of a box type, got " << value;
  return success();
}
