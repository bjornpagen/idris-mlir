// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The inline rule. The callee is final when it is decided, so the size is
// the size its callers copy, and the count of its calls was taken before
// any caller ran: a count read later would depend on which callers a
// worker had already finished.
#include "idr/Analysis/Inline.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

std::int64_t idr::inlining::sizeOf(FuncOp fn) {
  std::int64_t size = 0;
  fn.getBody().walk([&](Operation *) { ++size; });
  return size;
}

idr::inlining::Verdict idr::inlining::verdictOf(FuncOp fn, std::uint32_t calls, Cycle cycle) {
  std::int64_t size = 0;
  std::uint32_t callOps = 0;
  fn.getBody().walk([&](Operation *op) {
    ++size;
    if (isa<CallOpInterface>(op))
      ++callOps;
  });
  if (cycle == Cycle::On)
    return Keep{};
  bool leaf = callOps == 0 && size <= kLeafSize;
  bool cheap = (static_cast<std::int64_t>(calls) - 1) * (size - kSmall) <= kProduct;
  if (leaf || cheap)
    return Inline{size};
  return Keep{};
}
