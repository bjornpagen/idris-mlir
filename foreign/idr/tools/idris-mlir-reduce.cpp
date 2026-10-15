// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-reduce: mlir-reduce with the idr dialect and passes registered,
// for shrinking a module that makes a pass fail.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Tools/mlir-reduce/MlirReduceMain.h"

#include "idris_rt.h"

int main(int argc, char **argv) {
  // The folders run the runtime's big operations, whose GMP allocates where
  // a program's does, set while no other thread exists.
  idris_rt_gmp_init();
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  registry.insert<idr::IdrDialect>();
  // How a closure moves through the upstream ops that can hold one, and
  // the schedules the pipeline's interpreter runs, loaded with the
  // transform dialect.
  idr::registerFlowInterfaceExternalModels(registry);
  idr::target::registerScheduleLibrary(registry);
  mlir::MLIRContext context(registry);
  return mlir::failed(mlir::mlirReduceMain(argc, argv, context)) ? 1 : 0;
}
