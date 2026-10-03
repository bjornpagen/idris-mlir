// idr-specialize redirecting a call to a clone of its callee, as an action.
module idr.support;

import idr.mlir;

mlir::TypeID idr::support::SpecializeCloneAction::resolveTypeID() {
  static mlir::SelfOwningTypeID id;
  return id;
}

void idr::support::SpecializeCloneAction::print(llvm::raw_ostream &os) const {
  os << '`' << tag << '`';
}
