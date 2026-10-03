// idr.support:actions: transforms as actions of MLIR's action framework, so
// that a debug counter (-mlir-debug-counter=<tag>-skip=N,<tag>-count=M) can
// bisect them and -log-actions-to can list them. A skipped action is a
// transform that does not happen: the IR stays as it was, and valid. Each
// action's IR unit is the call it transforms.
export module idr.support:actions;

import idr.mlir;

export namespace idr::support {

// idr-specialize redirects a call to a clone of its callee.
struct SpecializeCloneAction : mlir::tracing::ActionImpl<SpecializeCloneAction> {
  // The action's identity, which MLIR's TypeID finds by this name.
  static mlir::TypeID resolveTypeID();
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
  void print(llvm::raw_ostream &os) const override;
};

// idr-specialize raises a call into a clone that takes its consumer.
struct RaiseAction : mlir::tracing::ActionImpl<RaiseAction> {
  static mlir::TypeID resolveTypeID();
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-raise";
  void print(llvm::raw_ostream &os) const override;
};

// idr-eval replaces a closed call by its results.
struct EvalCallAction : mlir::tracing::ActionImpl<EvalCallAction> {
  static mlir::TypeID resolveTypeID();
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-eval-call";
  void print(llvm::raw_ostream &os) const override;
};

// Runs `transform` as an action A on `op`, unless the context's action
// handler skips it; whether it ran. `transform` may erase `op`. Each user
// instantiates the template, so its body is here.
template <typename A>
bool perform(mlir::Operation *op, llvm::function_ref<void()> transform) {
  bool ran = false;
  mlir::IRUnit unit(op);
  op->getContext()->executeAction<A>(
      [&] {
        transform();
        ran = true;
      },
      unit);
  return ran;
}

} // namespace idr::support
