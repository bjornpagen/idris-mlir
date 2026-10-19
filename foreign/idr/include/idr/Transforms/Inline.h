// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline step of idr-optimize: a function's calls into final callees,
// inlined by the inline rule while the caller stays under its cap. (`inline`
// is a keyword, so the area's namespace is `inlining`.)
#ifndef IDR_TRANSFORMS_INLINE_H
#define IDR_TRANSFORMS_INLINE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Optimize.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "llvm/ADT/STLFunctionalExtras.h"

namespace idr::inlining {

// What one step did: the calls it inlined, and those the cap kept.
struct Step {
  unsigned inlined = 0;
  unsigned capped = 0;
};

// Inlines, in walk order, each idr.call `caller` holds when the step
// starts whose callee, as `callee` answers it, is final and inlined by the
// rule, or a member of the caller's component the call applies to a
// closure or suspension of a final function (beta reduction), while the
// caller stays within the cap. The caller loses Idris's
// proof of termination where it takes in a body without one. A callee that
// never returns leaves the rest of its call's block unreachable, which goes
// once the step's calls are all taken.
Step inlineCalls(idr::FuncOp caller,
                 llvm::function_ref<optimize::Callee(mlir::StringAttr)> callee);

} // namespace idr::inlining

#endif // IDR_TRANSFORMS_INLINE_H
