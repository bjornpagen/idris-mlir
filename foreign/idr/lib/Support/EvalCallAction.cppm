// idr.support:evalcallaction: idr-eval replacing a closed call by its
// results, as an action (perform).
export module idr.support:evalcallaction;

import idr.mlir;

export namespace idr::support {

// idr-eval replaces a closed call by its results.
struct EvalCallAction : mlir::tracing::ActionImpl<EvalCallAction> {
  // The action's identity, which MLIR's TypeID finds by this name.
  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-eval-call";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

} // namespace idr::support
