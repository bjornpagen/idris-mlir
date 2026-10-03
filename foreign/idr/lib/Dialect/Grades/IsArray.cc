// An array: a memref of a field type at no grade.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// One dynamic dimension in the identity layout: the shape the runtime's
// array cell has (a length, then the elements in order). An element is a
// field type at no grade, and not the world or the erased value, which
// have no runtime form to store.
bool idr::isArray(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() != 1 || !memref.isDynamicDim(0) ||
      !memref.getLayout().isIdentity() || memref.getMemorySpace())
    return false;
  Type element = memref.getElementType();
  return !isa<QType>(element) && !isWorld(element) && !isErased(element) && isFieldType(element);
}
