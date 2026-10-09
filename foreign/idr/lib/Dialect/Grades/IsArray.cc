// An array: a memref of rank 0 or 1 of a field type at no grade.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// At most one dimension, each dynamic, in the identity layout: the shapes
// the runtime's array cell has (a length, then the elements in order), an
// IORef being the cell of one element, whose length is 1 and no value
// carries. An element is a field type at no grade, and not the world or the
// erased value, which have no runtime form to store.
bool idr::isArray(Type type) {
  auto memref = dyn_cast<MemRefType>(type);
  if (!memref || memref.getRank() > 1 || memref.getNumDynamicDims() != memref.getRank() ||
      !memref.getLayout().isIdentity() || memref.getMemorySpace())
    return false;
  Type element = memref.getElementType();
  return !isa<QType>(element) && !isWorld(element) && !isErased(element) && isFieldType(element);
}

bool idr::isRank1Array(Type type) {
  return isArray(type) && cast<MemRefType>(type).getRank() == 1;
}
