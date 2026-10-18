// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-reduce: mlir-reduce with the idr dialect and passes registered,
// for shrinking a module that makes a pass fail, and with the dialect's
// reduction patterns, which simplify the ops the reducer cannot erase
// without leaving their uses without a value. Like idris-mlir-opt, it runs
// on the runtime's reserved-stack runner, on the tools' stack, so the
// nested constants MLIR's parser and printer recurse over are bounded by
// memory, not by the process's stack.
// PIN(mlir-recursion)

#include "idr/IR/IdrDialect.h"
#include "idr/InitIdr.h"
#include "idr/Support/Stack.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Reducer/ReductionPatternInterface.h"
#include "mlir/Tools/mlir-reduce/MlirReduceMain.h"
#include "llvm/ADT/SmallVectorExtras.h"

namespace {

// The values an op of a function's body computes, made ub.poison, which
// takes no operand: erasing the op would leave its uses without a value,
// which no candidate verifies with, while this keeps every use and drops
// the op's own. An op with regions stays, for the reducer to work inside,
// and a poison is already the simplest value.
struct PoisonResults : mlir::RewritePattern {
  explicit PoisonResults(mlir::MLIRContext *ctx)
      : RewritePattern(mlir::Pattern::MatchAnyOpTypeTag(), /*benefit=*/1, ctx) {}

  mlir::LogicalResult matchAndRewrite(mlir::Operation *op,
                                      mlir::PatternRewriter &rewriter) const override {
    if (op->getNumResults() == 0 || op->getNumRegions() != 0 ||
        mlir::isa<mlir::ub::PoisonOp>(op) || !op->getParentOfType<idr::FuncOp>())
      return mlir::failure();
    auto poison = [&](mlir::Type type) -> mlir::Value {
      return mlir::ub::PoisonOp::create(rewriter, op->getLoc(), type);
    };
    rewriter.replaceOp(op, llvm::map_to_vector(op->getResultTypes(), poison));
    return mlir::success();
  }
};

// The idr dialect's reduction patterns, which mlir-reduce's reduction tree
// gathers from every loaded dialect's interface.
struct IdrReductionPatterns : mlir::DialectReductionPatternInterface {
  explicit IdrReductionPatterns(mlir::Dialect *dialect)
      : DialectReductionPatternInterface(dialect) {}

  void populateReductionPatterns(mlir::RewritePatternSet &patterns) const override {
    patterns.add<PoisonResults>(patterns.getContext());
  }
};

int reduceMain(int argc, char **argv) {
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  // Upstream's dialects and extensions, as mlir-reduce has them, then
  // idr's, whose schedule library is written in upstream's transform ops.
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdrDialects(registry);
  // The reduction patterns, given to idr wherever this registry loads it,
  // so that no other tool carries the reducer's interface.
  registry.addExtension(+[](mlir::MLIRContext *, idr::IdrDialect *dialect) {
    dialect->addInterfaces<IdrReductionPatterns>();
  });
  mlir::MLIRContext context(registry);
  return mlir::failed(mlir::mlirReduceMain(argc, argv, context));
}

} // namespace

int main(int argc, char **argv) {
  return idr::support::runTool("idris-mlir-reduce", [&] { return reduceMain(argc, argv); });
}
