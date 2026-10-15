// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline rule. The callee is final when it is read, so the size is
// the size its callers copy, and the count of its calls was taken before
// any caller ran: a count read later would depend on which callers a
// worker had already finished.

#include "idr/Analysis/Inline.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

int64_t idr::inlineSize(FuncOp fn) {
  int64_t ops = 0;
  fn.getBody().walk([&](Operation *) { ++ops; });
  return ops;
}

bool idr::inlining::worthInlining(const Facts &callee, bool noInline) {
  if (callee.onCycle || noInline)
    return false;
  if (callee.leaf && callee.size <= kLeafSize)
    return true;
  return (static_cast<int64_t>(callee.calls) - 1) * (callee.size - kSmall) <= kProduct;
}
