// The facts of a function whose body takes in another's.
module idr.facts;

import idr.mlir;

using namespace mlir;
using namespace idr;

void facts::inlined(func::FuncOp into, func::FuncOp callee) {
  if (!callee || !callee->hasAttr("idr.total"))
    into->removeAttr("idr.total");
}
