// idr.support:specializecloneaction: idr-specialize redirecting a call to a
// clone of its callee, as an action (perform).
export module idr.support:specializecloneaction;

import idr.mlir;

export namespace idr::support {

// idr-specialize redirects a call to a clone of its callee.
struct SpecializeCloneAction : mlir::tracing::ActionImpl<SpecializeCloneAction> {
  // The action's identity, which MLIR's TypeID finds by this name.
  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

} // namespace idr::support
