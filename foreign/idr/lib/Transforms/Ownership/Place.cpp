// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place: the references of one function made explicit, after
// idr-rc graded every signature: the reuse rewrite at the sites Reuses
// decided, then the reshaping and the placement of the counts. It reads the
// module's analyses idr-rc computed before running it, and writes nothing
// outside its function: an entry argument it grades owned is one the
// signature already made owned.
#include "idr/Analysis/Ownership.h"
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

  StringRef getArgument() const override { return "idr-rc-place"; }
  StringRef getDescription() const override {
    return "Reuse dead cells and place the counts of one function";
  }

  void runOnOperation() override {
    FuncOp fn = getOperation();
    auto symbols = getCachedParentAnalysis<SymbolTable>();
    auto reuses = getCachedParentAnalysis<Reuses>();
    if (!symbols || !reuses) {
      fn.emitError("idr-rc-place: internal error: the module's SymbolTable or Reuses was not "
                   "computed");
      return signalPassFailure();
    }
    IRRewriter rewriter(fn.getContext());
    Counted counted;
    reuseAt(rewriter, reuses->get().sites(fn), counted);
    Classes classes(fn, counted);
    if (failed(reshape(rewriter, fn, counted, classes, symbols->get())))
      return signalPassFailure();
    place(rewriter, fn, classes, symbols->get());
  }
};

} // namespace

std::unique_ptr<Pass> createRcPlace() { return std::make_unique<RcPlace>(); }

} // namespace idr::ownership
