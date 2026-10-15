// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place: the references of one function made explicit, after
// idr-rc graded every signature: the reuse rewrite at the sites Reuses
// decided, then the reshaping and the placement of the counts. It reads
// what idr-rc built before running it, and writes nothing outside its
// function: an entry argument it grades owned is one the signature
// already made owned.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

using namespace mlir;

namespace idr::ownership {

namespace {

struct RcPlace : PassWrapper<RcPlace, OperationPass<FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(RcPlace)

  RcPlace(const Reuses &reuses, const CalleeEffects &callees) : reuses(reuses), callees(callees) {}

  StringRef getArgument() const override { return "idr-rc-place"; }
  StringRef getDescription() const override {
    return "Reuse dead cells and place the counts of one function";
  }

  void runOnOperation() override {
    FuncOp fn = getOperation();
    IRRewriter rewriter(fn.getContext());
    reuseAt(rewriter, reuses.sites(fn));
    if (failed(reshape(rewriter, fn, callees)))
      return signalPassFailure();
    place(rewriter, fn, callees);
  }

  const Reuses &reuses;
  const CalleeEffects &callees;
};

} // namespace

std::unique_ptr<Pass> createRcPlace(const Reuses &reuses, const CalleeEffects &callees) {
  return std::make_unique<RcPlace>(reuses, callees);
}

} // namespace idr::ownership
