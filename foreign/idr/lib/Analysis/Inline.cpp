// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline rule. The callee is final when it is decided, so the size is
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

idr::inlining::Facts idr::inlining::factsOf(FuncOp fn, unsigned calls, bool shared) {
  Facts facts{inlineSize(fn), false};
  StringAttr name = fn.getSymNameAttr();
  bool leaf = true;
  bool callsItself = false;
  fn.getBody().walk([&](CallOp call) {
    leaf = false;
    callsItself = callsItself || call.getCalleeAttr().getAttr() == name;
  });
  if (shared || callsItself || fn.getNoInline())
    return facts;
  facts.inlines = (leaf && facts.size <= kLeafSize) ||
                  (static_cast<int64_t>(calls) - 1) * (facts.size - kSmall) <= kProduct;
  return facts;
}
