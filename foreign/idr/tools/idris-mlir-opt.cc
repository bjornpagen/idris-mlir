// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered (DRV-OPT-1).

#include "idr/Idr.h"

#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

int main(int argc, char **argv) {
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdr(registry);
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "idris-mlir-opt: the idr dialect\n", registry));
}
