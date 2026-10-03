// idr.graph:fieldsof: the fields of the box an idr.con or idr.reuse builds.
export module idr.graph:fieldsof;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::graph {

// The fields of the box an idr.con or idr.reuse builds.
OperandRange fieldsOf(Operation *op) {
  if (auto con = dyn_cast<idr::ConOp>(op))
    return con.getFields();
  return cast<idr::ReuseOp>(op).getFields();
}

} // namespace idr::graph
