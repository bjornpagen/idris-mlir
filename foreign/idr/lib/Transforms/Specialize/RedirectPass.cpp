// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-redirect: each call of a function whose arguments compose a key, or
// whose result a dispatch consumes, requests its key's node and calls it.
// It is the step of idr-optimize's inner pipeline that runs after
// canonicalization and CSE, so it reads each call once the function is
// clean, and the ready set builds what it requested.
//
// The nodes are idr-optimize's table, read through the parent's cache. The
// table answers for a callee only when the callee is final, so no function
// reads a body another worker writes.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/IR/Arith.h"

namespace idr {
#define GEN_PASS_DEF_IDRREDIRECT
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Redirect : idr::impl::IdrRedirectBase<Redirect> {
  void runOnOperation() override {
    idr::FuncOp fn = getOperation();
    auto nodes = getCachedParentAnalysis<idr::specialize::Nodes>();
    if (!nodes) {
      fn.emitError("internal error: idr-redirect runs inside idr-optimize, which holds the "
                   "specialization nodes of its module");
      return signalPassFailure();
    }
    unsigned redirected = 0;
    bool changed = false;
    if (failed(nodes->get().redirectCalls(fn, redirected, changed)))
      return signalPassFailure();
    numRedirected += redirected;
    if (!changed)
      markAllAnalysesPreserved();
  }
};

} // namespace
