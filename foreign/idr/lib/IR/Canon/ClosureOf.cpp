// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The closure an apply runs, which its canonicalization turns into a call.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

using namespace mlir;
using namespace idr;

namespace idr::canon {

// When the callee is the one use of a linear value made from a closure and
// nothing else uses either, the closure is what runs. The pair only moves
// the closure into a linear position and out again, so going around it
// uses nothing twice.
Value closureOf(ApplyOp apply) {
  Value callee = apply.getCallee();
  auto use = callee.getDefiningOp<LinUseOp>();
  if (!use || !callee.hasOneUse())
    return callee;
  auto enter = use.getLinear().getDefiningOp<LinEnterOp>();
  if (!enter || !enter->hasOneUse())
    return callee;
  return enter.getValue();
}

} // namespace idr::canon
