// Whether a call whose results are unused may go.
module idr.facts;

import idr.mlir;

using namespace mlir;

bool idr::facts::canDrop(func::CallOp call) { return call->use_empty() && canMoveAcross(call); }
