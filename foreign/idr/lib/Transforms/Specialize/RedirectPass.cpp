// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-redirect: each call of a function whose arguments compose a key, or
// whose result a dispatch consumes, requests its key's node and calls it.
// It is the step of idr-optimize's inner pipeline that runs after
// canonicalization and CSE, so it reads each call once the function is
// clean, and the ready set builds what it requested.
//
// The nodes are idr-optimize's table for the run, given to the step when
// it is made. The table answers for a callee only when the callee is
// final, so no function reads a body another worker writes.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Dialect/Arith/IR/Arith.h"

namespace idr {
#define GEN_PASS_DEF_IDRREDIRECT
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct Redirect : idr::impl::IdrRedirectBase<Redirect> {
  Redirect(const idr::specialize::Nodes &nodes, Pass::Statistic &numRedirected)
      : nodes(nodes), numRedirected(numRedirected) {}

  void runOnOperation() override {
    FailureOr<unsigned> redirected = nodes.redirectCalls(getOperation());
    if (failed(redirected))
      return signalPassFailure();
    numRedirected += *redirected;
    if (*redirected == 0)
      markAllAnalysesPreserved();
  }

  const idr::specialize::Nodes &nodes;
  Pass::Statistic &numRedirected;
};

} // namespace

std::unique_ptr<Pass> idr::optimize::createRedirect(const specialize::Nodes &nodes,
                                                    Pass::Statistic &redirected) {
  return std::make_unique<Redirect>(nodes, redirected);
}
