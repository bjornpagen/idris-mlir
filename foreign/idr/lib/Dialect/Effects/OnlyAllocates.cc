// Whether an op, with everything in it, only computes.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

bool idr::onlyAllocates(Operation *op) {
  return !op->walk([](Operation *inner) {
              return ops::does(inner) == ops::Does::Nothing ? WalkResult::advance()
                                                            : WalkResult::interrupt();
            })
              .wasInterrupted();
}
