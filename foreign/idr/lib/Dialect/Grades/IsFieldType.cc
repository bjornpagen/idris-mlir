// The types a field of a constructor may have.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

bool idr::isFieldType(Type type) {
  if (isWorld(type) || isErased(type))
    return true;
  type = unrestricted(type);
  if (auto integer = dyn_cast<IntegerType>(type))
    return integer.isSignless() && llvm::is_contained({8u, 16u, 32u, 64u}, integer.getWidth());
  return isa<Float64Type, DataType, BoxType, FnType, LazyType, StrType, BigType, NatType>(type) ||
         isArray(type);
}
