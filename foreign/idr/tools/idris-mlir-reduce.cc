// idris-mlir-reduce: mlir-reduce with the idr dialect and passes registered,
// for shrinking a module that makes a pass fail.

#include "idr/Idr.h"

#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-reduce/MlirReduceMain.h"

int main(int argc, char **argv) {
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdr(registry);
  mlir::MLIRContext context(registry);
  return mlir::failed(mlir::mlirReduceMain(argc, argv, context)) ? 1 : 0;
}
