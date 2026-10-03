// The value a value was made from, seen through the linear positions it
// passed.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Value idr::throughLinear(Value value) {
  for (;;) {
    if (auto enter = value.getDefiningOp<LinEnterOp>()) {
      value = enter.getValue();
      continue;
    }
    auto use = value.getDefiningOp<LinUseOp>();
    auto enter = use ? use.getLinear().getDefiningOp<LinEnterOp>() : LinEnterOp();
    if (!enter)
      return value;
    value = enter.getValue();
  }
}
