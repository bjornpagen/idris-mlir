// The fields of the box an idr.con or idr.reuse builds.
module idr.graph;

import idr.mlir;
import idr.dialect;

using namespace mlir;

OperandRange idr::graph::fieldsOf(Operation *op) {
  if (auto con = dyn_cast<idr::ConOp>(op))
    return con.getFields();
  return cast<idr::ReuseOp>(op).getFields();
}
