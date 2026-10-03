// idr-specialize raising a call into a clone that takes its consumer, as an
// action.
module idr.support;

import idr.mlir;

mlir::TypeID idr::support::RaiseAction::resolveTypeID() {
  static mlir::SelfOwningTypeID id;
  return id;
}

void idr::support::RaiseAction::print(llvm::raw_ostream &os) const { os << '`' << tag << '`'; }
