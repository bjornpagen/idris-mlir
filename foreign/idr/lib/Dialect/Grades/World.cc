// The spelling !idr.world: the world at (one, plain).

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

Type idr::world(MLIRContext *ctx) {
  return graded({Quantity::One, Permission::Plain}, WorldType::get(ctx));
}
