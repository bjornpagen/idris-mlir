// The spelling !idr.erased: no carrier at (zero, plain).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::erased(MLIRContext *ctx) {
  return graded({Quantity::Zero, Permission::Plain}, NoneType::get(ctx));
}
