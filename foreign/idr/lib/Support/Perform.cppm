// idr.support:perform: transforms as actions of MLIR's action framework, so
// that a debug counter (-mlir-debug-counter=<tag>-skip=N,<tag>-count=M) can
// bisect them and -log-actions-to can list them. A skipped action is a
// transform that does not happen: the IR stays as it was, and valid. Each
// action's IR unit is the call it transforms.
export module idr.support:perform;

import idr.mlir;

export namespace idr::support {

// Runs `transform` as an action A on `op`, unless the context's action
// handler skips it; whether it ran. `transform` may erase `op`. Each user
// instantiates the template, so keep it thin.
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
