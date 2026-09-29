// Transforms as actions of MLIR's action framework, so that a debug counter
// (-mlir-debug-counter=<tag>-skip=N,<tag>-count=M) can bisect them and
// -log-actions-to can list them. A skipped action is a transform that does
// not happen: the IR stays as it was, and valid. Each action's IR unit is the
// call it transforms.
#pragma once

#include "mlir/IR/Action.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Unit.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

namespace idr {

// idr-specialize redirects a call to a clone of its callee.
struct SpecializeCloneAction : mlir::tracing::ActionImpl<SpecializeCloneAction> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(SpecializeCloneAction)
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

// idr-specialize raises a call into a clone that takes its consumer.
struct RaiseAction : mlir::tracing::ActionImpl<RaiseAction> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RaiseAction)
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-raise";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

// idr-eval replaces a closed call by its results.
struct EvalCallAction : mlir::tracing::ActionImpl<EvalCallAction> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(EvalCallAction)
  using ActionImpl::ActionImpl;
  static constexpr llvm::StringLiteral tag = "idr-eval-call";
  void print(llvm::raw_ostream &os) const override { os << '`' << tag << '`'; }
};

// Runs `transform` as an action A on `op`, unless the context's action
// handler skips it; whether it ran. `transform` may erase `op`.
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

} // namespace idr
