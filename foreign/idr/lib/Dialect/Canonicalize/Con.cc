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
  if (llvm::is_contained(adaptor.getFields(), Attribute()))
    return {};
  return ConAttr::get(getContext(), getCtor(), ArrayAttr::get(getContext(), adaptor.getFields()));
}
