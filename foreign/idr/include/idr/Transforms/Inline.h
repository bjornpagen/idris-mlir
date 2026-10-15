// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline step of idr-optimize: a function's calls into final callees,
// inlined by the inline rule while the caller stays under its cap. (`inline`
// is a keyword, so the area's namespace is `inlining`.)
#ifndef IDR_TRANSFORMS_INLINE_H
#define IDR_TRANSFORMS_INLINE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace idr::optimize {
class Node;
} // namespace idr::optimize

namespace idr::inlining {

// What one step did: the calls it inlined, and those the cap kept.
struct Step {
  unsigned inlined = 0;
  unsigned capped = 0;
};

// Inlines, in walk order, each idr.call `caller` holds when the step
// starts whose callee's node, as `nodeOf` answers it, is final and worth
// inlining, while the caller stays within the cap. A body that needs
// blocks of its own goes nowhere a single block must hold it. The caller
// loses Idris's proof of termination where it takes in a body without one.
Step inlineCalls(idr::FuncOp caller,
                 llvm::function_ref<const optimize::Node *(mlir::StringAttr)> nodeOf);

} // namespace idr::inlining

#endif // IDR_TRANSFORMS_INLINE_H
