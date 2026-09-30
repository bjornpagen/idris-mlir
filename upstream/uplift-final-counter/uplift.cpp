// Applies upstream's scf.while to scf.for uplift
// (populateUpliftWhileToForPatterns) to the module in argv[1], with the
// greedy driver's folding, and prints the result. No mlir-opt pass runs
// the uplift outside MLIR's own test passes.
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/Support/raw_ostream.h"

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  mlir::MLIRContext context;
  context.loadDialect<mlir::arith::ArithDialect, mlir::func::FuncDialect, mlir::scf::SCFDialect>();
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceFile<mlir::ModuleOp>(argv[1], &context);
  if (!module)
    return 1;
  mlir::RewritePatternSet patterns(&context);
  mlir::scf::populateUpliftWhileToForPatterns(patterns);
  if (mlir::failed(mlir::applyPatternsGreedily(*module, std::move(patterns))))
    return 1;
  module->print(llvm::outs());
  return 0;
}
