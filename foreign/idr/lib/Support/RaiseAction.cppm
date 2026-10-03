// idr.support:raiseaction: idr-specialize raising a call into a clone that
// takes its consumer, as an action (perform).
export module idr.support:raiseaction;

import idr.mlir;

export namespace idr::support {

// idr-specialize raises a call into a clone that takes its consumer.
struct RaiseAction : mlir::tracing::ActionImpl<RaiseAction> {
  // The action's identity, which MLIR's TypeID finds by this name.
  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-raise";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

} // namespace idr::support
