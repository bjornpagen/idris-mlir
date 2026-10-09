// The folds of idr.con: a constructor of constants is a constant, and a
// constructor rebuilt from the fields of a value of that constructor is the
// value (record eta).

#include "idr/Idr.h"

import idr.canon;

using namespace mlir;
using namespace idr;

OpFoldResult ConOp::fold(FoldAdaptor adaptor) {
  if (Value value = canon::eta(*this))
    return value;
  // A field folds only as a constant the dialect builds at its type. A
  // poison field is the program's value where control never arrives, which
  // no constant holds: the constructor stays an op around it, and idr-lower
  // builds it.
  for (auto [field, operand] : llvm::zip_equal(adaptor.getFields(), getFields()))
    if (!field || !canon::buildable(field, operand.getType()))
      return {};
  return ConAttr::get(getContext(), getCtor(), ArrayAttr::get(getContext(), adaptor.getFields()));
}
