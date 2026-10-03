// The spelling !idr.erased: no carrier at (0, .).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::erased(MLIRContext *ctx) {
  return graded({Quantity::Zero, Permission::None}, NoneType::get(ctx));
}
