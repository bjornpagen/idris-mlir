// Whether an op, or something in it, may perform IO.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

bool idr::performsIO(Operation *op) {
  return op->walk([](Operation *inner) {
             return ops::does(inner) == ops::Does::IO ? WalkResult::interrupt()
                                                      : WalkResult::advance();
           })
      .wasInterrupted();
}
