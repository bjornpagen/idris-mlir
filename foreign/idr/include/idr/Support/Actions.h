// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Transforms as actions of MLIR's action framework, so that
// -log-actions-to lists them, --log-actions-tags narrowing the list, and in
// idris-mlir-opt a debug counter (-mlir-debug-counter=<tag>-skip=N,
// <tag>-count=M) can bisect them. A skipped action is a transform that does
// not happen: the IR stays as it was, and valid. Each action's IR unit is
// the op it transforms: a call, a function, a loop, a constructor, the op
// whose value becomes a constant.
#ifndef IDR_SUPPORT_ACTIONS_H
#define IDR_SUPPORT_ACTIONS_H

#include "mlir/IR/Action.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Unit.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

namespace idr::support {

// `tag` in backquotes: how every tagged action prints.
void printTag(llvm::raw_ostream &os, llvm::StringRef tag);

// An action whose only distinction is its tag, `Derived::tag`. The passes
// that count or skip a transform (perform) each name one; the identity, the
// printing and the TypeID are this. The TypeID is owned here, one per
// action, a constant identity: MLIR finds it by `resolveTypeID`.
template <typename Derived>
struct TaggedAction : mlir::tracing::ActionImpl<Derived> {
  using mlir::tracing::ActionImpl<Derived>::ActionImpl;

  static mlir::TypeID resolveTypeID() {
    static mlir::SelfOwningTypeID id;
    return id;
  }

  void print(llvm::raw_ostream &os) const override { printTag(os, Derived::tag); }
};

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

#endif // IDR_SUPPORT_ACTIONS_H
