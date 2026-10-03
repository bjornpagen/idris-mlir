// The spelling !idr.world: the world at (1, .).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::world(MLIRContext *ctx) {
  return graded({Quantity::One, Permission::None}, WorldType::get(ctx));
}
