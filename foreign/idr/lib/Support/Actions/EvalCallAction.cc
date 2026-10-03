// idr-eval replacing a closed call by its results, as an action.
module idr.support;

import idr.mlir;

mlir::TypeID idr::support::EvalCallAction::resolveTypeID() {
  static mlir::SelfOwningTypeID id;
  return id;
}

void idr::support::EvalCallAction::print(llvm::raw_ostream &os) const { os << '`' << tag << '`'; }
