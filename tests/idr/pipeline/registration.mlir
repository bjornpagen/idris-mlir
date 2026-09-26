// RUN: idris-mlir-opt --help | FileCheck %s
// rule: DRV-OPT-1
// CHECK-DAG: --idr-check-input
// CHECK-DAG: --idr-entry
// CHECK-DAG: --idr-lower
// CHECK-DAG: --idr-pipeline
// CHECK-DAG: --idr-tail-loops
// CHECK-DAG: --convert-to-llvm
// CHECK-DAG: --inline
