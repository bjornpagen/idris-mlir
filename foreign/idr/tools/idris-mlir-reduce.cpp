// idris-mlir-reduce: mlir-reduce with the idr dialect and passes registered,
// for shrinking a module that makes a pass fail.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-reduce/MlirReduceMain.h"

int main(int argc, char **argv) {
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  registry.insert<idr::IdrDialect>();
  mlir::MLIRContext context(registry);
  return mlir::failed(mlir::mlirReduceMain(argc, argv, context)) ? 1 : 0;
}
